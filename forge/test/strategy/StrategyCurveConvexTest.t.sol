// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvex.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCurveConvexTest is BaseStrategyTest {

    address constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant uniV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    ICrvMinter constant minter = ICrvMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    uint24[] fee = [3000];
    uint[3][4] testParams = [[2, 0, 3], [2, 1, 1], [1, 0, 7], [1, 0, 7]];

    StrategyCurveConvex strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyCurveConvex();
        else strategy = StrategyCurveConvex(payable(_impl));
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
        strategy.setConvexPid(strategy.NO_PID());
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
        strategy.setConvexPid(1);

        console.log("setConvexPid valid pid switches to Convex");
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
        strategy.setConvexPid(strategy.NO_PID());

        console.log("setCrvMintable false not expecting harvest");
        skip(1 days);
        strategy.setCrvMintable(false);
        strategy.harvest();
        assertEq(vault.balance(), bal, "Harvested");

        console.log("setCrvMintable true expecting harvest CRV");
        skip(1 days);
        strategy.setCrvMintable(true);
        strategy.harvest();
        assertGt(vault.balance(), bal, "Not harvested");
    }

    function test_rewards() external {
        if (strategy.rewardPool() != address(0)) {
            strategy.booster().earmarkRewards(strategy.pid());
        }

        _depositIntoVault(user, wantAmount);
        skip(1 days);

        // if convex
        if (strategy.rewardPool() != address(0)) {
            console.log("Claim rewards on Convex");
            IConvexRewardPool(strategy.rewardPool()).getReward(address(strategy));
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
        strategy.setSkipEarmarkRewards(true);
        console.log("Harvest");
        strategy.harvest();
        assertEq(vault.balance(), bal, "Harvested");
        uint periodFinishNew = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertEq(periodFinishNew, periodFinish, "periodFinish updated");
    }
}