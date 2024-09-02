// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWeatteryV1 {
    enum LotteryPhase {
        salePhase,
        drawingPhase,
        claimPhase,
        stalePhase
    }

    enum WeatherState {
        Sunny,
        Cloudy,
        Rainy,
        Snowy
    }

    function charge() external payable;
    function refund(uint256 _amount) external payable;
    function startLottery() external;
    function bet(uint256 _bet, WeatherState _weatherState) external;
    function draw() external;
    function claim() external;
    function emergencyStop() external;
    function resumeProtocol() external;
    function setEmergencyRefundBalance() external;
    function emergencyRefund() external;
    function retrieveAllProtocolFee() external;
    function setGovernanceToken(address _WGT) external;
    function claimAirdrop(uint256 _amount, bytes32[] calldata _merkleProof) external;
    function fetchWeatherVotes(WeatherState _weatherState) external returns (uint256);
}
