// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/WeatteryV1.sol";
import "../src/IWeatteryV1.sol";
import "../src/WBT.sol";

contract WeatteryTest is Test {
    WeatteryV1 public weattery;
    WeatteryBettingToken public wbt;

    function setUp() public {
        WeatteryV1 weatteryImpl = new WeatteryV1();
        wbt = new WeatteryBettingToken();

        ERC1967Proxy proxy =
            new ERC1967Proxy(address(weatteryImpl), abi.encodeWithSignature("initialize(address)", address(wbt)));
        weattery = WeatteryV1(address(proxy));

        wbt.registerMintable(address(weattery));

        vm.deal(address(this), 100 ether);
        vm.deal(address(1), 100 ether);
        vm.deal(address(2), 100 ether);
        vm.deal(address(3), 100 ether);
        vm.deal(address(4), 100 ether);
    }

    function testStartLottery() public {
        console.log("Test Contract Address:", address(this));
        console.log("Owner of weattery Contract Address:", weattery.owner());
        console.log("Owner of WBT Contract Address:", wbt.owner());
        console.log("Weatery V1 Contract Address:", address(weattery));
        console.log("WBT Contract Address:", address(wbt));

        // before start the lottery
        assertEq(weattery.paused(), false);
        assertEq(uint8(weattery.lotteryPhase()), uint8(IWeatteryV1.LotteryPhase.stalePhase));

        weattery.startLottery();

        // after start the lottery
        assertEq(uint8(weattery.lotteryPhase()), uint8(IWeatteryV1.LotteryPhase.salePhase));
        assertEq(weattery.weatherVote(IWeatteryV1.WeatherState.Sunny), 0);
        assertEq(weattery.weatherVote(IWeatteryV1.WeatherState.Cloudy), 0);
        assertEq(weattery.weatherVote(IWeatteryV1.WeatherState.Rainy), 0);
        assertEq(weattery.weatherVote(IWeatteryV1.WeatherState.Snowy), 0);
        assertEq(weattery.getParticipantLength(), 0);
        assertEq(weattery.isDrawed(), false);
        assertEq(weattery.startedTimestamp(), block.timestamp);
    }

    function testCharge() public {
        vm.prank(address(1));
        weattery.charge{value: 0.1 ether}();

        assertEq(wbt.balanceOf(address(1)), 0.1 ether);
    }

    function testChargeAndThenRefund() public {
        vm.prank(address(1));
        weattery.charge{value: 0.1 ether}();

        vm.prank(address(1));
        weattery.refund(0.1 ether);

        assertEq(wbt.balanceOf(address(1)), 0);
        assertEq(address(weattery).balance, 0.1 ether * weattery.protocolFee() / 100);

        vm.prank(address(5));
        vm.expectRevert("You don't have enough balance to refund");
        weattery.refund(0.1 ether);
    }

    function testBet() public {
        weattery.startLottery();

        vm.prank(address(1));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(1));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Sunny);

        assertEq(wbt.balanceOf(address(weattery)), 0.1 ether);
        assertEq(weattery.weatherVote(IWeatteryV1.WeatherState.Sunny), 0.1 ether);
    }

    function testOnlyAtomicBet() public {
        weattery.startLottery();

        vm.prank(address(1));
        weattery.charge{value: 0.2 ether}();
        vm.prank(address(1));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Sunny);
        vm.prank(address(1));
        vm.expectRevert("You can bet only one time on each Sale Phase");
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Cloudy);
    }

    function testDraw() public {
        weattery.startLottery();

        vm.prank(address(1));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(2));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(3));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(4));
        weattery.charge{value: 0.1 ether}();

        vm.prank(address(1));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Sunny);
        vm.prank(address(2));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Cloudy);
        vm.prank(address(3));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Rainy);
        vm.prank(address(4));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Snowy);

        vm.expectRevert("You can draw only on Draw Phase");
        weattery.draw();

        vm.warp(block.timestamp + weattery.saleDuration());
        vm.prank(address(1));
        weattery.draw();
        assertEq(weattery.isDrawed(), true);

        vm.expectRevert("Already Drawed");
        weattery.draw();

        // FYI, each values of enum WeatherState are Sunny : 0 (address 1 voted), Cloudy : 1 (address 2 voted), Rainy : 2 (address 3 voted), Snowy : 3 (address 4 voted)
        assertEq(
            weattery.claimableToken(address(uint160(uint8(weattery.weatherState()) + 1))),
            0.1 ether * (weattery.winWeight()) / 100
        );
    }

    function testClaim() public {
        weattery.startLottery();

        vm.prank(address(1));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(2));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(3));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(4));
        weattery.charge{value: 0.1 ether}();

        vm.prank(address(1));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Sunny);
        vm.prank(address(2));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Cloudy);
        vm.prank(address(3));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Rainy);
        vm.prank(address(4));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Snowy);

        vm.prank(address(1));
        vm.expectRevert("You can claim only on Claim Phase");
        weattery.claim();

        vm.warp(block.timestamp + weattery.saleDuration());
        weattery.draw();

        vm.prank(address(1));
        vm.expectRevert("You can claim only on Claim Phase");
        weattery.claim();

        // FYI, each values of enum WeatherState are Sunny : 0 (address 1 voted), Cloudy : 1 (address 2 voted), Rainy : 2 (address 3 voted), Snowy : 3 (address 4 voted)
        address winner = address(uint160(uint8(weattery.weatherState()) + 1));

        vm.warp(block.timestamp + weattery.drawDuration());
        vm.prank(winner);
        weattery.claim();
        assertEq(wbt.balanceOf(winner), 0.1 ether * (weattery.winWeight()) / 100);
        assertEq(weattery.claimableToken(winner), 0);
    }

    function testNoClaimAvailableAfterStaled() public {
        weattery.startLottery();

        vm.prank(address(1));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(2));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(3));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(4));
        weattery.charge{value: 0.1 ether}();

        vm.prank(address(1));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Sunny);
        vm.prank(address(2));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Cloudy);
        vm.prank(address(3));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Rainy);
        vm.prank(address(4));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Snowy);

        vm.prank(address(1));
        vm.expectRevert("You can claim only on Claim Phase");
        weattery.claim();

        vm.warp(block.timestamp + weattery.saleDuration());
        weattery.draw();

        // FYI, each values of enum WeatherState are Sunny : 0 (address 1 voted), Cloudy : 1 (address 2 voted), Rainy : 2 (address 3 voted), Snowy : 3 (address 4 voted)
        address winner = address(uint160(uint8(weattery.weatherState()) + 1));

        vm.prank(winner);
        vm.expectRevert("You can claim only on Claim Phase");
        weattery.claim();

        vm.warp(block.timestamp + weattery.drawDuration() + weattery.claimDuration());
        vm.expectRevert("You can claim only on Claim Phase");
        vm.prank(winner);
        weattery.claim();
    }

    function testMulticallFetchWeatherVotes() public {
        weattery.startLottery();

        vm.prank(address(1));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(2));
        weattery.charge{value: 0.2 ether}();
        vm.prank(address(3));
        weattery.charge{value: 0.3 ether}();
        vm.prank(address(4));
        weattery.charge{value: 0.4 ether}();

        vm.prank(address(1));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Sunny);
        vm.prank(address(2));
        weattery.bet(0.2 ether, IWeatteryV1.WeatherState.Cloudy);
        vm.prank(address(3));
        weattery.bet(0.3 ether, IWeatteryV1.WeatherState.Rainy);
        vm.prank(address(4));
        weattery.bet(0.4 ether, IWeatteryV1.WeatherState.Snowy);

        bytes memory callSunny =
            abi.encodeWithSelector(weattery.fetchWeatherVotes.selector, IWeatteryV1.WeatherState.Sunny);
        bytes memory callCloudy =
            abi.encodeWithSelector(weattery.fetchWeatherVotes.selector, IWeatteryV1.WeatherState.Cloudy);
        bytes memory callRainy =
            abi.encodeWithSelector(weattery.fetchWeatherVotes.selector, IWeatteryV1.WeatherState.Rainy);
        bytes memory callSnowy =
            abi.encodeWithSelector(weattery.fetchWeatherVotes.selector, IWeatteryV1.WeatherState.Snowy);

        bytes[] memory calls = new bytes[](4);

        calls[0] = callSunny;
        calls[1] = callCloudy;
        calls[2] = callRainy;
        calls[3] = callSnowy;

        bytes[] memory results = weattery.multicall(calls);

        uint256 sunnyResult = abi.decode(results[0], (uint256));
        uint256 cloudyResult = abi.decode(results[1], (uint256));
        uint256 rainyResult = abi.decode(results[2], (uint256));
        uint256 snowyResult = abi.decode(results[3], (uint256));

        assertEq(sunnyResult, 0.1 ether);
        assertEq(cloudyResult, 0.2 ether);
        assertEq(rainyResult, 0.3 ether);
        assertEq(snowyResult, 0.4 ether);
    }

    function testEmergencyStop() public {
        weattery.startLottery();

        vm.prank(address(1));
        weattery.charge{value: 0.1 ether}();
        vm.prank(address(2));
        weattery.charge{value: 0.2 ether}();
        vm.prank(address(3));
        weattery.charge{value: 0.3 ether}();
        vm.prank(address(4));
        weattery.charge{value: 0.4 ether}();

        vm.prank(address(1));
        weattery.bet(0.1 ether, IWeatteryV1.WeatherState.Sunny);
        vm.prank(address(2));
        weattery.bet(0.2 ether, IWeatteryV1.WeatherState.Cloudy);
        vm.prank(address(3));
        weattery.bet(0.3 ether, IWeatteryV1.WeatherState.Rainy);
        vm.prank(address(4));
        weattery.bet(0.4 ether, IWeatteryV1.WeatherState.Snowy);

        vm.expectRevert(
            "Setting Emergency refund Balance can only be initiated after the protocol has been stopped via emergencyStop"
        );
        weattery.setEmergencyRefundBalance();

        weattery.emergencyStop();

        vm.expectRevert(
            "Emergency refund can only be initiated after setting the Emergency Refund Balance via setEmergencyRefundBalance"
        );
        weattery.emergencyRefund();

        weattery.setEmergencyRefundBalance();

        vm.expectRevert(
            "The protocol can only be resumed after the Emergency Refund Balance has been distributed via emergencyRefund"
        );
        weattery.resumeProtocol();

        weattery.emergencyRefund();

        assertEq(wbt.balanceOf(address(1)), 0.1 ether);
        assertEq(wbt.balanceOf(address(2)), 0.2 ether);
        assertEq(wbt.balanceOf(address(3)), 0.3 ether);
        assertEq(wbt.balanceOf(address(4)), 0.4 ether);

        weattery.resumeProtocol();
    }

    receive() external payable {}
}
