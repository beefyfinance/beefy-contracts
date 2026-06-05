// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseStrategyTest.t.sol";
import "../../../contracts/BIFI/strategies/Common/BaseAllToNativeFactoryStrat.sol";

abstract contract BaseAllToNativeFactoryTest is BaseStrategyTest {

    function claimRewardsToStrat() internal virtual {
        BaseAllToNativeFactoryStrat(payable(vault.strategy())).claim();
    }

    function test_lockedProfit() external {
        BaseAllToNativeFactoryStrat strategy = BaseAllToNativeFactoryStrat(payable(vault.strategy()));
        uint initStratBal = strategy.balanceOf();

        vm.prank(strategy.keeper());
        strategy.setHarvestOnDeposit(false);
        _depositIntoVault(user, wantAmount);
        skip(delay);

        uint stratBalBefore = strategy.balanceOf();
        beforeHarvest();
        strategy.harvest();

        uint stratBal = strategy.balanceOf();
        uint lockedProfit = strategy.lockedProfit();
        assertGt(lockedProfit, 0, "lockedProfit == 0 (Not harvested");
        assertEq(stratBal, stratBalBefore, "Only profit should be locked");
        assertEq(lockedProfit, strategy.totalLocked(), "lockedProfit != totalLocked");
        assertEq(stratBal, strategy.balanceOfWant() + strategy.balanceOfPool() - lockedProfit, "Strat.balanceOf != want + pool - lockedProfit");

        console.log("User2");
        VaultUser user2 = new VaultUser();
        deal(vault.want(), address(user2), wantAmount, dealWithAdjust);
        _depositIntoVault(user2, wantAmount);
        uint stratBalAfterUser2 = strategy.balanceOf();
        assertEq(stratBalAfterUser2, initStratBal + wantAmount * 2, "Strat balance should double");

        skip(strategy.lockDuration());
        assertEq(strategy.lockedProfit(), 0, "lockedProfit != 0 after lockDuration");
        assertEq(strategy.balanceOf(), stratBalAfterUser2 + lockedProfit, "Strat balance should grow by lockedProfit");

        user.withdrawAll(vault);
        user2.withdrawAll(vault);
        uint user1Bal = want.balanceOf(address(user));
        uint user2Bal = want.balanceOf(address(user2));
        uint profitToInitialShares = lockedProfit * initStratBal / (initStratBal + wantAmount * 2);
        uint usersProfit = lockedProfit - profitToInitialShares;
        assertApproxEqAbs(usersProfit / 2, user1Bal - wantAmount, 1, "User1 should earn lockedProfit/2");
        assertApproxEqAbs(usersProfit / 2, user2Bal - wantAmount, 1, "User2 should earn lockedProfit/2");
    }

    function test_rewards() external {
        BaseAllToNativeFactoryStrat strategy = BaseAllToNativeFactoryStrat(payable(vault.strategy()));
        vm.prank(strategy.keeper());
        strategy.setHarvestOnDeposit(false);

        _depositIntoVault(user, wantAmount);
        skip(delay);

        claimRewardsToStrat();
        beforeHarvest();

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
        address native = strategy.native();
        uint nativeBal = IERC20(native).balanceOf(address(strategy));
        console.log("WETH %18e", nativeBal);

        (, bytes memory data0) = address(strategy).call(abi.encodeWithSignature("lpToken0()"));
        (, bytes memory data1) = address(strategy).call(abi.encodeWithSignature("lpToken1()"));
        address lp0; address lp1;
        if (data0.length > 0) {
            lp0 = abi.decode(data0, (address));
            uint bal = IERC20(lp0).balanceOf(address(strategy));
            console.log("lpToken0 %18e", bal * 1e18 / 10 ** IERC20Extended(lp0).decimals());
        }
        if (data1.length > 0) {
            lp1 = abi.decode(data1, (address));
            uint bal = IERC20(lp1).balanceOf(address(strategy));
            console.log("lpToken1 %18e", bal * 1e18 / 10 ** IERC20Extended(lp1).decimals());
        }
        if (lp0 != native && lp1 != native) {
            assertEq(nativeBal, 0, "Native not swapped");
        }
    }

    receive() external payable {}
}