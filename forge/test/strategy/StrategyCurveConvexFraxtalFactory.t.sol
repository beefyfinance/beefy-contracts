// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvexFraxtalFactory.sol";
import "./BaseAllToNativeFactoryTest.t.sol";

contract StrategyCurveConvexFraxtalFactoryTest is BaseAllToNativeFactoryTest {

    StrategyCurveConvexFraxtalFactory strategy;

    function createStrategy(address _impl) internal override returns (address) {
        cacheOraclePrices();
        if (_impl == a0) strategy = new StrategyCurveConvexFraxtalFactory();
        else strategy = StrategyCurveConvexFraxtalFactory(payable(_impl));
        return address(strategy);
    }

    function test_setConvexPid() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;
        uint pid = strategy.pid();

        address rewardPool = strategy.rewardPool();
        _depositIntoVault(user, wantAmount);

        uint rewardPoolBal = IConvexRewardPool(rewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");

        console.log("setConvexPid NO_PID switches to Curve");
        vm.startPrank(strategy.owner());
        strategy.setConvexPid(strategy.NO_PID());
        vm.stopPrank();
        rewardPoolBal = IConvexRewardPool(rewardPool).balanceOf(address(strategy));
        assertEq(rewardPoolBal, 0, "RewardPool balance != 0");
        uint gaugeBal = IRewardsGauge(strategy.gauge()).balanceOf(address(strategy));
        assertEq(vault.balance(), gaugeBal, "Gauge balance != vault balance");
        user.withdrawAll(vault);
        uint userBal = want.balanceOf(address(user));
        assertLe(userBal, wantAmount, "Expected userBal <= wantAmount");
        assertGt(userBal, wantAmount * 99 / 100, "Expected userBal > wantAmount * 99 / 100");

        _depositIntoVault(user, userBal);
        console.log("setConvexPid bad pid reverts");
        vm.startPrank(strategy.owner());
        vm.expectRevert();
        strategy.setConvexPid(pid + 1);
        vm.stopPrank();

        console.log("setConvexPid valid pid switches to Convex");
        vm.prank(strategy.owner());
        strategy.setConvexPid(pid);
        rewardPoolBal = IConvexRewardPool(rewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");
        gaugeBal = IRewardsGauge(strategy.gauge()).balanceOf(address(strategy));
        assertEq(gaugeBal, 0, "Gauge balance != 0");
        user.withdrawAll(vault);
        uint userBalFinal = want.balanceOf(address(user));
        assertLe(userBalFinal, userBal, "Expected userBalFinal <= userBal");
        assertGt(userBalFinal, userBal * 99 / 100, "Expected userBalFinal > userBal * 99 / 100");
    }

    function test_setCrvMintable() external {
        // revert all calls to minter.mint
        vm.mockCallRevert(
            address(strategy.minter()),
            abi.encodeWithSelector(ICrvMinter.mint.selector, strategy.gauge()),
            "MINTER_CALLED"
        );

        // no mint if convex
        if (strategy.rewardPool() != address(0)) {
            strategy.harvest();
        }

        console.log("setConvexPid NO_PID");
        vm.startPrank(strategy.owner());
        strategy.setConvexPid(strategy.NO_PID());
        vm.stopPrank();

        console.log("setCrvMintable false not expecting mint");
        vm.prank(strategy.keeper());
        strategy.setCrvMintable(false);
        strategy.harvest();

        console.log("setCrvMintable true expecting mint");
        vm.prank(strategy.keeper());
        strategy.setCrvMintable(true);
        vm.expectRevert("MINTER_CALLED");
        strategy.harvest();
    }

    function cacheOraclePrices() internal {
        address sfrxUSDMinter = 0xBFc4D34Db83553725eC6c768da71D2D9c1456B55;
        address owner = OwnableUpgradeable(sfrxUSDMinter).owner();
        bytes memory data = abi.encodeWithSignature("setOracleTimeTolerance(uint256)", 100_000_000);
        vm.prank(owner);
        (bool success,) = sfrxUSDMinter.call(data);
        assertTrue(success, "sfrxUSDMinter call failed");

        address sfrxUSDOracle = 0x1B680F4385f24420D264D78cab7C58365ED3F1FF;
        bytes memory callData = abi.encodeWithSignature("latestRoundData()");
        (, bytes memory resData) = sfrxUSDOracle.staticcall(callData);
        vm.mockCall(sfrxUSDOracle, callData, resData);
    }
}