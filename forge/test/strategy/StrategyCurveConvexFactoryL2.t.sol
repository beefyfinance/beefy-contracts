// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvexL2Factory.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCurveConvexL2FactoryTest is BaseStrategyTest {

    StrategyCurveConvexL2Factory strategy;

    function createStrategy(address _impl) internal override returns (address) {
        cacheOraclePrices();
        if (_impl == a0) strategy = new StrategyCurveConvexL2Factory();
        else strategy = StrategyCurveConvexL2Factory(payable(_impl));
        return address(strategy);
    }

    function test_initWithNoPid() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        IVault vaultNoPid = IVault(address(vaultV7));
        StrategyCurveConvexL2Factory strategyNoPid = new StrategyCurveConvexL2Factory();

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

    function test_rewards() external {
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
        }
    }

    function cacheOraclePrices() internal {
        address opSnxRate = 0x913bd76F7E1572CC8278CeF2D6b06e2140ca9Ce2;
        if (opSnxRate.code.length > 0) {
            bytes memory _callData = abi.encodeWithSignature("rateWithSafetyChecks(bytes32)", 0x7345544800000000000000000000000000000000000000000000000000000000);
            (, bytes memory _res) = opSnxRate.call(_callData);
            (uint _price,,) = abi.decode(_res, (uint, bool, bool));
            vm.mockCall(opSnxRate, _callData, abi.encode(_price, 0, 0));

            _callData = abi.encodeWithSelector(bytes4(keccak256("anyRateIsInvalidAtRound(bytes32[],uint256[])")));
            vm.mockCall(opSnxRate, _callData, abi.encode(0));
        }
    }
}