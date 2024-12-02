// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Pendle/StrategyEquilibria.sol";
import "./BaseAllToNativeFactoryTest.t.sol";

contract StrategyEquilibriaTest is BaseAllToNativeFactoryTest {

    StrategyEquilibria strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyEquilibria();
        else strategy = StrategyEquilibria(payable(_impl));
        cacheOraclePrices();
        return address(strategy);
    }

    function beforeHarvest() internal override {
        vm.roll(block.number + 1); // pass lastRewardBlock check in PendleMarket
        strategy.claim();
    }

    function claimRewardsToStrat() internal override {
        vm.roll(block.number + 1); // pass lastRewardBlock check in PendleMarket
        strategy.claim();
        strategy.claim();
    }

    function test_setEqbPid() public {
        // only if currently NOT on Eqb
        if (address(strategy.rewardPool()) != address(0)) {
            console.log("Skip EQB");
            return;
        }

        uint eqbPid = vm.envOr("PID", uint(0));
        if (eqbPid == 0) {
            console.log("Skip no pid");
            return;
        }

        _depositIntoVault(user, wantAmount);
        console.log("Set pid", eqbPid);
        vm.startPrank(strategy.keeper());
        strategy.setEqbPid(eqbPid, false);
        vm.stopPrank();
    }

    function test_setEqbNoPid() public {
        if (address(strategy.rewardPool()) == address(0)) {
            console.log("Skip not Eqb");
            return;
        }

        uint pid = strategy.pid();
        IRewardPool rewardPool = strategy.rewardPool();
        _depositIntoVault(user, wantAmount);

        uint rewardPoolBal = rewardPool.balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");

        console.log("NO_PID switches to Pendle");
        vm.startPrank(strategy.keeper());
        strategy.setEqbPid(strategy.NO_PID(), false);
        vm.stopPrank();
        rewardPoolBal = rewardPool.balanceOf(address(strategy));
        assertEq(rewardPoolBal, 0, "RewardPool balance after NO_PID != 0");
        uint stratBal = want.balanceOf(address(strategy));
        uint stratBalOfWant = strategy.balanceOfWant();
        assertEq(vault.balance(), stratBal, "Strat want balance != vault balance");
        assertEq(stratBalOfWant, stratBal, "Strat want balance != strat balanceOfWant");
        user.withdrawAll(vault);
        uint userBal = want.balanceOf(address(user));
        assertLe(userBal, wantAmount, "Expected userBal <= wantAmount");
        assertGt(userBal, wantAmount * 99 / 100, "Expected userBal > wantAmount * 99 / 100");

        _depositIntoVault(user, userBal);
        console.log("Bad pid reverts");
        vm.startPrank(strategy.owner());
        vm.expectRevert("!market");
        strategy.setEqbPid(pid - 1, false);
        vm.stopPrank();

        console.log("Valid pid switches to Eqb");
        vm.prank(strategy.keeper());
        strategy.setEqbPid(pid, false);
        rewardPoolBal = rewardPool.balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");
        stratBal = want.balanceOf(address(strategy));
        assertEq(stratBal, 0, "Strat want balance != 0");
        user.withdrawAll(vault);
        uint userBalFinal = want.balanceOf(address(user));
        assertLe(userBalFinal, userBal, "Expected userBalFinal <= userBal");
        assertGt(userBalFinal, userBal * 99 / 100, "Expected userBalFinal > userBal * 99 / 100");
    }

    function test_depositAndWithdraw() public override {
        if (address(strategy.rewardPool()) != address(0)) {
            super.test_depositAndWithdraw();
            return;
        }

        // custom test for NO_PID as balanceOfPool is always 0 as strat simply holds want
        _depositIntoVault(user, wantAmount);
        assertEq(want.balanceOf(address(user)), 0, "User balance != 0 after deposit");
        assertGe(vault.balance(), wantAmount, "Vault balance < wantAmount");

        uint vaultBal = vault.balance();
        uint balOfPool = strategy.balanceOfPool();
        uint balOfWant = strategy.balanceOfWant();
        assertGe(balOfWant, wantAmount, "balOfPool < wantAmount"); // if deposit fee could be GT want * 99 / 100
        assertEq(balOfWant, vaultBal, "balOfPool != vaultBal");
        assertEq(balOfPool, 0, "Strategy.balanceOfPool != 0");

        console.log("Panic");
        vm.prank(strategy.keeper());
        strategy.panic();
        uint vaultBalAfterPanic = vault.balance();
        uint balOfPoolAfterPanic = strategy.balanceOfPool();
        uint balOfWantAfterPanic = strategy.balanceOfWant();
        // Vault balances are correct after panic.
        assertEq(vaultBalAfterPanic, vaultBal, "vaultBalAfterPanic"); // vaultBal * 99 / 100
        assertEq(balOfWantAfterPanic, balOfWant, "balOfWantAfterPanic != balOfWant");
        assertEq(balOfPoolAfterPanic, 0, "balOfPoolAfterPanic != 0");

        console.log("Unpause");
        vm.prank(strategy.keeper());
        strategy.unpause();
        uint vaultBalAfterUnpause = vault.balance();
        uint balOfPoolAfterUnpause = strategy.balanceOfPool();
        uint balOfWantAfterUnpause = strategy.balanceOfWant();
        assertEq(vaultBalAfterUnpause, vaultBalAfterPanic, "vaultBalAfterUnpause");
        assertEq(balOfWantAfterUnpause, balOfWant, "balOfWantAfterUnpause != balOfWant");
        assertEq(balOfPoolAfterUnpause, 0, "balOfPoolAfterUnpause != 0");

        console.log("Withdrawing all");
        user.withdrawAll(vault);

        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, wantAmount, "Expected wantBalanceFinal <= wantAmount");
        assertGt(wantBalanceFinal, wantAmount * 99 / 100, "Expected wantBalanceFinal > wantAmount * 99 / 100");
    }

    function test_redeem() public {
        // only if currently on Eqb
        if (address(strategy.rewardPool()) == address(0)) {
            console.log("Skip not Eqb");
            return;
        }

        vm.prank(strategy.keeper());
        strategy.setHarvestOnDeposit(false);
        _depositIntoVault(user, wantAmount);
        skip(1 days);

        uint minRedeemDuration = strategy.xEqb().minRedeemDuration();
        vm.prank(strategy.keeper());
        strategy.setRedeemEqb(true, 1 days);

        strategy.harvest();
        uint redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 1, "Not 1 redeem after first harvest");
        (,,uint256 endTime) = strategy.xEqb().getUserRedeem(address(strategy), 0);

        skip(12 hours);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 1, "Should be still 1 redeem before delay");

        skip(13 hours);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 2, "Not 2 redeems after redeem delay");

        skip(minRedeemDuration);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 2, "Not 2 redeems after 1st redeem duration");
        (,, uint256 endTimeNext) = strategy.xEqb().getUserRedeem(address(strategy), 0);
        assertGt(endTimeNext, endTime, "1st redeem not updated");

        // disable redeems
        vm.prank(strategy.keeper());
        strategy.setRedeemEqb(false, 0);
        skip(25 hours);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 2, "Redeems updated when 'redeemEqb' is false");

        // enable redeems but increase delay to not create new redeems
        vm.prank(strategy.keeper());
        strategy.setRedeemEqb(true, minRedeemDuration + 1 weeks);
        skip(minRedeemDuration);
        deal(address(strategy.xEqb()), address(strategy), 10e18);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 1, "Not redeemed after re-enable");
        uint xEqbBal = strategy.xEqb().balanceOf(address(strategy));
        assertGt(xEqbBal, 0, "Should not redeem xEqb");
    }

    function test_manualRedeem() public {
        // only if currently on Eqb
        if (address(strategy.rewardPool()) == address(0)) {
            console.log("Skip not Eqb");
            return;
        }

        uint minRedeemDuration = strategy.xEqb().minRedeemDuration();
        vm.prank(strategy.keeper());
        strategy.setRedeemEqb(false, 0);

        _depositIntoVault(user, wantAmount);
        skip(delay);
        strategy.harvest();

        // redeem manually
        vm.prank(strategy.keeper());
        strategy.redeemAll();
        uint redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 1, "Not redeemed manually");
        uint xEqbBal = strategy.xEqb().balanceOf(address(strategy));
        assertEq(xEqbBal, 0, "Not all xEqb redeemed");

        // finalize manually
        IERC20 eqb = IERC20(strategy.booster().eqb());
        uint eqbBal = eqb.balanceOf(address(strategy));
        skip(minRedeemDuration + 1);
        vm.prank(strategy.keeper());
        strategy.finalizeRedeem(0);
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 0, "Not finalized manually");
        assertGt(eqb.balanceOf(address(strategy)), eqbBal, "EQB not finalized");
    }

    function cacheOraclePrices() internal {
        address dolomiteOracle = 0xBfca44aB734E57Dc823cA609a0714EeC9ED06cA0;
        if (dolomiteOracle.code.length > 0) {
            bytes memory _callData = abi.encodeWithSignature("getPrice(address)", 0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
            (, bytes memory _res) = dolomiteOracle.staticcall(_callData);
            uint _price = abi.decode(_res, (uint));
            vm.mockCall(dolomiteOracle, _callData, abi.encode(_price));

            _callData = abi.encodeWithSignature("getPrice(address)", 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
            (, _res) = dolomiteOracle.staticcall(_callData);
            _price = abi.decode(_res, (uint));
            vm.mockCall(dolomiteOracle, _callData, abi.encode(_price));
        }
    }

}