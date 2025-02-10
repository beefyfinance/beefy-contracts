// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvexFactory.sol";
import "./BaseAllToNativeFactoryTest.t.sol";

contract StrategyCurveConvexFactoryTest is BaseAllToNativeFactoryTest {

    StrategyCurveConvexFactory strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyCurveConvexFactory();
        else strategy = StrategyCurveConvexFactory(payable(_impl));

//        vm.prank(0x4fED5491693007f0CD49f4614FFC38Ab6A04B619);
//        0x8d6cE71ab8c98299c1956247CA9aaEC080DD2df3.call(hex'84aad7fd0000000000000000000000005f98805a4e8be255a32880fdec7f6728c6568ba0000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000060000000000000000000000000e592427a0aece92de3edee1f18e0157c05861564000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000840000000000000000000000000000000000000000000000000000000000000144c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000008d6ce71ab8c98299c1956247ca9aaec080dd2df3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000abcdef0abcdef000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000425f98805a4e8be255a32880fdec7f6728c6568ba00001f4a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000');

        return address(strategy);
    }

    function test_initWithNoPid() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        IVault vaultNoPid = IVault(address(vaultV7));
        StrategyCurveConvexFactory strategyNoPid = new StrategyCurveConvexFactory();

        deal(address(want), address(user), wantAmount);

        vaultV7.initialize(IStrategyV7(address(strategyNoPid)), "TestVault", "testVault", 0);
        BaseAllToNativeFactoryStrat.Addresses memory commons = BaseAllToNativeFactoryStrat.Addresses({
            want: address(want),
            depositToken: strategy.depositToken(),
            factory: address(strategy.factory()),
            vault: address(vaultNoPid),
            swapper: strategy.swapper(),
            strategist: address(user)
        });
        address[] memory rewards = new address[](strategy.rewardsLength());
        for (uint i; i < strategy.rewardsLength(); ++i) {
            rewards[i] = strategy.rewards(i);
        }
        console.log("Init Strategy NO_PID");
        strategyNoPid.initialize(strategy.gauge(), strategy.NO_PID(), rewards, commons);

        user.approve(address(want), address(vaultNoPid), wantAmount);
        user.depositAll(vaultNoPid);
        user.withdrawAll(vaultNoPid);
        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, wantAmount, "Expected wantBalanceFinal <= wantAmount");
        assertGt(wantBalanceFinal, wantAmount * 99 / 100, "Expected wantBalanceFinal > wantAmount * 99 / 100");
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

    function test_earmark() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        // pass periodFinish
        skip(7 days);
        _depositIntoVault(user, wantAmount);
        uint bal = vault.balance();

        uint rewardsAvailable = strategy.rewardsAvailable();
        assertEq(rewardsAvailable, 0, "Expected 0 rewardsAvailable");

        uint periodFinish = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertLt(periodFinish, block.timestamp, "periodFinish not ended");

        console.log("Harvest");
        strategy.harvest();
        // in case of lockedProfit harvested balance is not available right away
        skip(1 days);
        assertGt(vault.balance(), bal, "Not Harvested");
        periodFinish = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertGt(periodFinish, block.timestamp, "periodFinish not updated");
    }

    function test_skipEarmark() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        // pass periodFinish
        skip(7 days);
        _depositIntoVault(user, wantAmount);
        uint bal = vault.balance();

        uint rewardsAvailable = strategy.rewardsAvailable();
        assertEq(rewardsAvailable, 0, "Expected 0 rewardsAvailable");

        uint periodFinish = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertLt(periodFinish, block.timestamp, "periodFinish not ended");

        console.log("SkipEarmarkRewards");
        vm.prank(strategy.keeper());
        strategy.setSkipEarmarkRewards(true);
        console.log("Harvest");
        strategy.harvest();
        assertEq(vault.balance(), bal, "Harvested");
        uint periodFinishNew = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertEq(periodFinishNew, periodFinish, "periodFinish updated");
    }
}