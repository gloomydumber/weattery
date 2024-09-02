// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IWeatteryV1} from "./IWeatteryV1.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {WeatteryBettingToken} from "./WBT.sol";
import {WeatteryGovernanceToken} from "./WGT.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract WeatteryV1 is UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, IWeatteryV1 {
    address public WBT; // Weattery Betting Token
    address public WGT; // Weattery Governance Token, would be used on Governance (consensus for setting Fee, phase time, etc...)
    uint256 public startedTimestamp;
    uint256 public saleDuration;
    uint256 public drawDuration;
    uint256 public claimDuration;
    uint256 public protocolFee;
    uint256 public winWeight;
    bytes32 public merkleRoot;
    bool public isDrawed;
    bool public isEmergencyRefundBalanceSet;
    address[] public participant;

    LotteryPhase public lotteryPhase;
    WeatherState public weatherState;

    mapping(address => mapping(WeatherState => uint256)) individualVote;
    mapping(address => uint256) emergencyRefundBalance;
    mapping(WeatherState => uint256) public weatherVote;
    mapping(address => uint256) public claimableToken;
    mapping(address => bool) public isAirdropClaimed;

    event gameStarted(uint256 startedTimestamp);
    event charged(address indexed charger, uint256 amount);
    event refunded(address indexed recipient, uint256 amount);
    event betted(address indexed better, WeatherState weatherState, uint256 amount);
    event drawed(address indexed drawer, uint256 drawedTimestamp);
    event claimed(address indexed claimer, uint256 amount, uint256 claimedTimestamp);
    event emergencyStopped();
    event emergencyResumed();
    event AirdropClaimed(address indexed claimant, uint256 amount);

    modifier OnlyAtomicBet() {
        require(individualVote[msg.sender][WeatherState.Sunny] == 0, "You can bet only one time on each Sale Phase");
        require(individualVote[msg.sender][WeatherState.Cloudy] == 0, "You can bet only one time on each Sale Phase");
        require(individualVote[msg.sender][WeatherState.Rainy] == 0, "You can bet only one time on each Sale Phase");
        require(individualVote[msg.sender][WeatherState.Snowy] == 0, "You can bet only one time on each Sale Phase");
        _;
    }

    function initialize(address _WBT) public initializer {
        __Ownable_init(_msgSender());
        __Pausable_init();
        __UUPSUpgradeable_init();

        WBT = _WBT;
        lotteryPhase = LotteryPhase.stalePhase;
        saleDuration = 5 minutes;
        drawDuration = 3 minutes;
        claimDuration = 2 minutes;
        protocolFee = 5;
        winWeight = 150;
    }

    /**
     * @dev Charge $WBT (Weattery Betting Token) to do bet.
     * The amount to charge would be sent as msg.value.
     *
     */
    function charge() external payable {
        require(!paused(), "The protocol is currently stopped due to an issue.");

        WeatteryBettingToken(WBT).mint(msg.sender, msg.value);
        emit charged(msg.sender, msg.value);
    }

    /**
     * @dev Refund $WBT (Weattery Betting Token) and get Ether, fee would be charged to Protocol.
     *
     * @param _amount The Amout value to refund $WBT (Weattery Betting Token) and get Ether.
     */
    function refund(uint256 _amount) external payable {
        require(!paused(), "The protocol is currently stopped due to an issue.");

        uint256 refundAmount = _amount * (100 - protocolFee) / 100;

        // CHECK
        require(WeatteryBettingToken(WBT).balanceOf(msg.sender) >= _amount, "You don't have enough balance to refund");
        require(address(this).balance >= refundAmount, "The protocol has not enough Ether value");

        // EFFECT
        WeatteryBettingToken(WBT).burn(msg.sender, _amount);

        // INTERACTIONS
        (bool success,) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund transfer failed");

        emit refunded(msg.sender, refundAmount);
    }

    /**
     * @dev Initilize and Reset values to start the lottery.
     *
     */
    function startLottery() external onlyOwner {
        require(!paused(), "The protocol is currently stopped due to an issue.");
        require(fetchLotteryPhase() == LotteryPhase.stalePhase, "Game could be started only on Stale Phase");

        uint256 participantLength = getParticipantLength();

        if (participantLength > 0) {
            for (uint256 i = 0; i < participantLength; ++i) {
                individualVote[participant[i]][WeatherState.Sunny] = individualVote[participant[i]][WeatherState.Cloudy]
                = individualVote[participant[i]][WeatherState.Rainy] =
                    individualVote[participant[i]][WeatherState.Snowy] = 0;

                claimableToken[participant[i]] = 0;
            }

            delete participant;
        }

        weatherVote[WeatherState.Sunny] =
            weatherVote[WeatherState.Cloudy] = weatherVote[WeatherState.Rainy] = weatherVote[WeatherState.Snowy] = 0;
        isDrawed = false;
        lotteryPhase = LotteryPhase.salePhase;
        startedTimestamp = block.timestamp;

        emit gameStarted(startedTimestamp);
    }

    /**
     * @dev Charge $WBT (Weattery Betting Token) to do bet.
     *
     * @param _amount The Amout value to bet with $WBT (Weattery Betting Token).
     * @param _weatherState The weatherState to bet.
     */
    function bet(uint256 _amount, WeatherState _weatherState) external OnlyAtomicBet {
        require(!paused(), "The protocol is currently stopped due to an issue.");
        require(fetchLotteryPhase() == LotteryPhase.salePhase, "You can bet only on Sale Phase");

        // CHECK
        require(WeatteryBettingToken(WBT).balanceOf(msg.sender) >= _amount, "You don't have enough balance to bet");

        // EFFECT
        // This contract can call transferFrom of $WBT without approve()
        WeatteryBettingToken(WBT).transferFrom(msg.sender, address(this), _amount);

        // INTERACTIONS
        participant.push(msg.sender);
        individualVote[msg.sender][_weatherState] = _amount;
        weatherVote[_weatherState] += _amount;

        emit betted(msg.sender, _weatherState, _amount);
    }

    /**
     * @dev Fetch current phase of lottery.
     *
     */
    function fetchLotteryPhase() internal returns (LotteryPhase) {
        require(!paused(), "The protocol is currently stopped due to an issue");

        if (startedTimestamp == 0) {
            lotteryPhase = LotteryPhase.stalePhase;
            return lotteryPhase;
        }

        uint256 currentTime = block.timestamp;
        uint256 saleEnd = startedTimestamp + saleDuration;
        uint256 drawEnd = saleEnd + drawDuration;
        uint256 claimEnd = drawEnd + claimDuration;

        if (currentTime >= saleEnd && currentTime < drawEnd) {
            lotteryPhase = LotteryPhase.drawingPhase;
        } else if (currentTime >= drawEnd && currentTime < claimEnd) {
            lotteryPhase = LotteryPhase.claimPhase;
        } else if (currentTime >= claimEnd) {
            lotteryPhase = LotteryPhase.stalePhase;
        }

        return lotteryPhase;
    }

    /**
     * @dev Draws the lottery
     * While this operation incurs a gas cost, it benefits other participants.
     * The operator who calls this function may be considered for future airdrops.
     *
     */
    function draw() external {
        require(fetchLotteryPhase() == LotteryPhase.drawingPhase, "You can draw only on Draw Phase");
        require(!isDrawed, "Already Drawed");

        fetchWeather();

        for (uint256 i = 0; i < participant.length; ++i) {
            if (individualVote[participant[i]][weatherState] != 0) {
                uint256 bettedAmount = individualVote[participant[i]][weatherState];

                individualVote[participant[i]][weatherState] = 0;
                claimableToken[participant[i]] = bettedAmount * winWeight / 100;
            }
        }

        isDrawed = true;
        emit drawed(msg.sender, block.timestamp);
    }

    /**
     * @dev Claim tokens.
     *
     */
    function claim() external {
        require(fetchLotteryPhase() == LotteryPhase.claimPhase, "You can claim only on Claim Phase");

        // CHECK
        require(claimableToken[msg.sender] != 0, "You don't have tokens to claimable");

        // EFFECTS
        uint256 claimableAmount = claimableToken[msg.sender];
        claimableToken[msg.sender] = 0;

        // INTERACTIONS
        WeatteryBettingToken(WBT).mint(msg.sender, claimableAmount);

        emit claimed(msg.sender, claimableAmount, block.timestamp);
    }

    /**
     * @dev Retrieves real-time weather information from an off-chain oracle.
     * Since the deployed chain operates on an isolated network (Upside Network) and doesn't support Chainlink,
     * the weather data is generated pseudo-randomly with each call.
     *
     */
    function fetchWeather() internal returns (WeatherState) {
        require(!paused(), "The protocol is currently stopped due to an issue.");
        require(lotteryPhase == LotteryPhase.drawingPhase);
        weatherState =
            WeatherState(uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % 4);

        return weatherState;
    }

    /**
     * @dev Fetch current votes of specific weather state.
     * It could be multicalled by {multicall} function.
     *
     * @param _weatherState the sepcific state of weather to fetch.
     */
    function fetchWeatherVotes(WeatherState _weatherState) external view returns (uint256) {
        require(!paused(), "The protocol is currently stopped due to an issue.");
        return weatherVote[_weatherState];
    }

    /**
     * @dev Multicall function that executes multiple fetchWeatherVotes calls using delegatecall.
     * This function ensures only {fetchWeatherVotes} calls are allowed.
     *
     * @param data Array of encoded function calls to fetchWeatherVotes.
     * @return results Array of the results of each function call.
     */
    function multicall(bytes[] calldata data) external returns (bytes[] memory results) {
        results = new bytes[](data.length);

        for (uint256 i = 0; i < data.length; i++) {
            bytes4 selector = bytes4(data[i][:4]);

            require(
                selector == this.fetchWeatherVotes.selector,
                "only fetchWeatherVotes function is available for multicall"
            );

            (bool success, bytes memory result) = address(this).delegatecall(data[i]);
            require(success, "delegatecall failed");
            results[i] = result;
        }
    }

    /**
     * @dev Halts the protocol operations immediately in case of a critical situation.
     * This function should only be invoked during emergency scenarios.
     *
     */
    function emergencyStop() external onlyOwner {
        require(!paused(), "The protocol is already stopped");
        _pause();

        emit emergencyStopped();
    }

    /**
     * @dev Sets the Emergency Refund Balance for all participants.
     * This function can only be called after the protocol has been paused using {emergencyStop}.
     * It is a crucial step in the emergency process, ensuring that each participant's refund balance is calculated based on their previous votes.
     *
     * Before proceeding, the function checks that the protocol is paused and that there are participants to distribute the refund balance to.
     * If these conditions are met, it iterates through each participant and their respective weather states to calculate and store their refund balances.
     *
     * Once this process is completed, the Emergency Refund Balance is considered set, and the protocol is prepared for the {emergencyRefund} function to distribute the refunds.
     */
    function setEmergencyRefundBalance() external onlyOwner {
        require(
            paused(),
            "Setting Emergency refund Balance can only be initiated after the protocol has been stopped via emergencyStop"
        );

        isEmergencyRefundBalanceSet = true;

        uint256 participantLength = getParticipantLength();
        require(participantLength != 0, "There are no participants to distribute the refund balance to");
        uint256 weatherStateLength = uint256(type(WeatherState).max) + 1;

        for (uint256 i = 0; i < participantLength; ++i) {
            address user = participant[i];
            for (uint256 j = 0; j < weatherStateLength; ++j) {
                WeatherState _weatherState = IWeatteryV1.WeatherState(j);
                if (individualVote[user][_weatherState] != 0) {
                    emergencyRefundBalance[user] = individualVote[user][_weatherState];
                }
            }
        }
    }

    /**
     * @dev Initiates an emergency refund of all Ether held by the protocol.
     * This function can only be called after {emergencyStop} and {setEmergencyRefundBalance} has been invoked.
     * If a user cannot receive their refund, the refund amount will be sent to the owner instead.
     *
     */
    function emergencyRefund() external onlyOwner {
        require(
            paused(), "Emergency refund can only be initiated after the protocol has been stopped via emergencyStop"
        );
        require(
            isEmergencyRefundBalanceSet,
            "Emergency refund can only be initiated after setting the Emergency Refund Balance via setEmergencyRefundBalance"
        );

        uint256 participantLength = getParticipantLength();

        for (uint256 i = 0; i < participantLength; ++i) {
            address user = participant[i];
            uint256 amount = emergencyRefundBalance[user];

            emergencyRefundBalance[user] = 0;
            WeatteryBettingToken(WBT).transfer(user, amount);
        }

        isEmergencyRefundBalanceSet = false;
    }

    /**
     * @dev Resumes the protocol operations after they have been stopped.
     * This function can only be called if the protocol is currently paused.
     * Before resuming, the function checks that the Emergency Refund Balance has not been set.
     * This is important because if the Emergency Refund Balance is set, it indicates that there are pending refunds that need to be distributed to participants.
     * Allowing the protocol to resume while these refunds are still pending could result in participants losing their refunds.
     * Therefore, the protocol can only be resumed after these refunds have been fully processed using the {emergencyRefund} function.
     * After the protocol is resumed, the lottery phase will be set to the Stale Phase.
     *
     */
    function resumeProtocol() external onlyOwner {
        require(paused(), "The protocol is not stopped");
        require(
            !isEmergencyRefundBalanceSet,
            "The protocol can only be resumed after the Emergency Refund Balance has been distributed via emergencyRefund"
        );

        lotteryPhase = LotteryPhase.stalePhase;

        _unpause();

        emit emergencyResumed();
    }

    /**
     * @dev Retrieves all Protocol Fee to Protocol Owner.
     */
    function retrieveAllProtocolFee() external onlyOwner {
        (bool success,) = owner().call{value: address(this).balance}("");
        require(success, "Transfer Protocol Fee to owner failed.");
    }

    /**
     * @dev Set Address of Weattery Governance Token.
     */
    function SetGovernanceToken(address _WGT) external onlyOwner {
        require(WGT == address(0), "token address is already set");
        WGT = _WGT;
    }

    /**
     * @dev Returns the number of participants in the current round.
     *
     * @return participant.length
     */
    function getParticipantLength() public view returns (uint256) {
        return participant.length;
    }

    /**
     * @dev Sets the Merkle Root value to be used for a future airdrop.
     *
     * @param _merkleRoot The Merkle Root that will be used to verify airdrop eligibility.
     */
    function setMerkleRoot(bytes32 _merkleRoot) extenral onlyOwner {
        merkleRoot = _merkleRoot;
    }

    /**
     * @dev Allows users to claim their Weattery Governance Tokens (WGT) through an airdrop.
     * The claimable amount is pre-calculated from off-chain.
     * This function just represents a future availability of airdrop.
     *
     * @param _amount The amount of tokens the user is eligible to claim, determined off-chain.
     * @param _merkleProof The Merkle proof that verifies the user's eligibility to claim the tokens.
     */
    function claimAirdrop(uint256 _amount, bytes32[] calldata _merkleProof) external {
        require(!isAirdropClaimed[msg.sender], "Airdrop already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(MerkleProof.verify(_merkleProof, merkleRoot, leaf), "Invalid merkle proof");

        isAirdropClaimed[msg.sender] = true;
        WeatteryGovernanceToken(WGT).transfer(msg.sender, _amount);

        emit AirdropClaimed(msg.sender, _amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        (bool success,) = newImplementation.call{value: address(this).balance}("");
        require(success, "Transfer Protocol Fee to New Implementation failed.");
    }
}
