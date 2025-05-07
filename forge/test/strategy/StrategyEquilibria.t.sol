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

//        vm.prank(0x4fED5491693007f0CD49f4614FFC38Ab6A04B619);
//        0xbf0449E4C9a997800EedA1193625Ecd35A3d175e.call(hex'84aad7fd000000000000000000000000940181a94a35a4569e4529a3cdfb74e38fd9863100000000000000000000000042000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000060000000000000000000000000be6d8f0d05cc4be24d5167a3ef062215be6d18a5000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000840000000000000000000000000000000000000000000000000000000000000124c04b8d59000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000bf0449e4c9a997800eeda1193625ecd35a3d175effffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000abcdef0abcdef0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b940181a94a35a4569e4529a3cdfb74e38fd986310000c8420000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000');

//        vm.prank(strategy.owner());
//        strategy.setRewardMinAmount(0x4200000000000000000000000000000000000006, 1e14);
        return address(strategy);
    }

    function beforeHarvest() internal override {
        vm.roll(block.number + 1); // pass lastRewardBlock check in PendleMarket
        strategy.claim();
//        deal(0x4200000000000000000000000000000000000006, address(strategy), 1e18);
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
        strategy.setEqbPid(pid == 0 ? 1 : pid - 1, false);
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