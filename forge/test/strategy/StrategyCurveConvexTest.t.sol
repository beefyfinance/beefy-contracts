// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvex.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCurveConvexTest is BaseStrategyTest {

    StrategyCurveConvex strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyCurveConvex();
        else strategy = StrategyCurveConvex(payable(_impl));
//        vm.prank(strategy.keeper());
//        strategy.setCrvMintable(true);
        return address(strategy);
    }

    function test_initWithNoPid() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        IVault vaultNoPid = IVault(address(vaultV7));
        StrategyCurveConvex strategyNoPid = new StrategyCurveConvex();

        vaultV7.initialize(IStrategyV7(address(strategyNoPid)), "TestVault", "testVault", 0);
        StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
            vault: address(vaultNoPid),
            unirouter: strategy.unirouter(),
            keeper: strategy.keeper(),
            strategist: address(user),
            beefyFeeRecipient: strategy.beefyFeeRecipient(),
            beefyFeeConfig: address(strategy.beefyFeeConfig())
        });
        address[] memory rewards = new address[](strategy.rewardsLength());
        for (uint i; i < strategy.rewardsLength(); ++i) {
            rewards[i] = strategy.rewards(i);
        }
        console.log("Init Strategy NO_PID");
        strategyNoPid.initialize(address(want), strategy.gauge(), strategy.NO_PID(), strategy.depositToken(), rewards, commons);

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
        uint noPid = strategy.NO_PID();
        vm.prank(strategy.owner());
        strategy.setConvexPid(noPid);
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
        vm.expectRevert();
        strategy.setConvexPid(pid + 1);

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
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        _depositIntoVault(user, wantAmount);
        uint bal = vault.balance();

        console.log("setConvexPid NO_PID");
        uint noPid = strategy.NO_PID();
        vm.prank(strategy.owner());
        strategy.setConvexPid(noPid);

        console.log("setCrvMintable false not expecting harvest");
        skip(1 days);
        vm.prank(strategy.keeper());
        strategy.setCrvMintable(false);
        strategy.harvest();
        assertEq(vault.balance(), bal, "Harvested");

        console.log("setCrvMintable true expecting harvest CRV");
        skip(1 days);
        vm.prank(strategy.keeper());
        strategy.setCrvMintable(true);
        strategy.harvest();
        // in case of lockedProfit harvested balance is not available right away
        skip(1 days);
        assertGt(vault.balance(), bal, "Not harvested");
    }

    function test_rewards() external {
        if (strategy.rewardPool() != address(0)) {
            if (IConvexRewardPool(strategy.rewardPool()).periodFinish() < block.timestamp) {
                strategy.booster().earmarkRewards(strategy.pid());
            }
        }

        _depositIntoVault(user, wantAmount);
        skip(1 days);

        // if convex
        if (strategy.rewardPool() != address(0)) {
            console.log("Claim rewards on Convex");
            IConvexRewardPool(strategy.rewardPool()).getReward(address(strategy), true);
        } else {
            console.log("Claim rewards on Curve");
            if (strategy.isCurveRewardsClaimable()) {
                IRewardsGauge(strategy.gauge()).claim_rewards(address(strategy));
            }
            if (strategy.isCrvMintable()) {
                vm.startPrank(address(strategy));
                strategy.minter().mint(strategy.gauge());
                vm.stopPrank();
            }
        }

        for (uint i; i < strategy.rewardsLength(); ++i) {
            uint bal = IERC20(strategy.rewards(i)).balanceOf(address(strategy));
            console.log(IERC20Extended(strategy.rewards(i)).symbol(), bal);
        }

        console.log("Harvest");
        strategy.harvest();

        for (uint i; i < strategy.rewardsLength(); ++i) {
            uint bal = IERC20(strategy.rewards(i)).balanceOf(address(strategy));
            console.log(IERC20Extended(strategy.rewards(i)).symbol(), bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
        uint nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        console.log("WETH", nativeBal);
        assertEq(nativeBal, 0, "Native not swapped");
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