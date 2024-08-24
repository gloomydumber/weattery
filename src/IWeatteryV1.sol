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
    function emergencyRefund() external;
    function startLottery() external;
    function bet(uint256 _bet, WeatherState _weatherState) external;
    function draw() external;
    function claim() external;
    function retrieveAllProtocolFee() external;
    function SetGovernanceToken(address _WGT) external;
    function claimAirdrop(uint256 _amount, bytes32[] calldata _merkleProof) external;
    function fetchWeatherVotes(WeatherState _weatherState) external returns (uint256);
}
