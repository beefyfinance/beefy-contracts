// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Morpho/StrategyMorpho.sol";
import "./BaseAllToNativeFactoryTest.t.sol";

contract StrategyMorphoTest is BaseAllToNativeFactoryTest {

    StrategyMorpho strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyMorpho();
        else strategy = StrategyMorpho(payable(_impl));
        return address(strategy);
    }

    function beforeHarvest() internal override {
        vm.prank(strategy.owner());
        strategy.addWantAsReward();
        for (uint i; i < strategy.rewardsLength(); i++) {
            deal(strategy.rewards(i), address(strategy), 1e18);
        }
    }

    function test_depositAndWithdraw() public override {
        _depositIntoVault(user, wantAmount);
        assertEq(want.balanceOf(address(user)), 0, "User balance != 0 after deposit");
        assertGe(vault.balance() + 1, wantAmount, "Vault balance < wantAmount");

        uint vaultBal = vault.balance();
        uint balOfPool = strategy.balanceOfPool();
        uint balOfWant = strategy.balanceOfWant();
        assertGe(balOfPool + 1, wantAmount, "balOfPool < wantAmount"); // if deposit fee could be GT want * 99 / 100
        assertEq(balOfPool, vaultBal, "balOfPool != vaultBal");
        assertEq(balOfWant, 0, "Strategy.balanceOfWant != 0");

        console.log("Panic");
        vm.prank(strategy.keeper());
        strategy.panic();
        uint vaultBalAfterPanic = vault.balance();
        uint balOfPoolAfterPanic = strategy.balanceOfPool();
        uint balOfWantAfterPanic = strategy.balanceOfWant();
        // Vault balances are correct after panic.
        assertEq(vaultBalAfterPanic, vaultBal, "vaultBalAfterPanic"); // vaultBal * 99 / 100
        assertLe(balOfPoolAfterPanic, 0, "balOfPoolAfterPanic");
        assertGt(balOfPool, balOfPoolAfterPanic, "balOfPool");
        assertGt(balOfWantAfterPanic, balOfWant, "balOfWantAfterPanic");

        console.log("Unpause");
        vm.prank(strategy.keeper());
        strategy.unpause();
        uint vaultBalAfterUnpause = vault.balance();
        uint balOfPoolAfterUnpause = strategy.balanceOfPool();
        uint balOfWantAfterUnpause = strategy.balanceOfWant();
        assertEq(vaultBalAfterUnpause + 1, vaultBalAfterPanic, "vaultBalAfterUnpause");
        assertEq(balOfWantAfterUnpause, 0, "balOfWantAfterUnpause != 0");
        assertEq(balOfPoolAfterUnpause, vaultBalAfterUnpause, "balOfPoolAfterUnpause");

        console.log("Withdrawing all");
        user.withdrawAll(vault);

        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, wantAmount, "Expected wantBalanceFinal <= wantAmount");
        assertGe(wantBalanceFinal + 2, wantAmount, "Expected wantBalanceFinal + 2 >= wantAmount");
    }

    function test_depositWithHod() external override {
        _depositIntoVault(user, wantAmount);
        uint pps = vault.getPricePerFullShare();
        assertGe(pps, 1e18, "Initial pps < 1");
        assertGe(vault.balance() + 1, wantAmount, "Vault balance < wantAmount");

        console.log("setHarvestOnDeposit true");
        vm.prank(strategy.keeper());
        strategy.setHarvestOnDeposit(true);
        skip(delay);
        deal(vault.want(), address(user), wantAmount, dealWithAdjust);

        beforeHarvest();
        // trigger harvestOnDeposit
        _depositIntoVault(user, wantAmount);
        // in case of lockedProfit harvested balance is not available right away
        skip(delay);
        assertGt(vault.getPricePerFullShare(), pps, "Not harvested");
        uint vaultBal = vault.balance();

        console.log("Withdrawing all");
        user.withdrawAll(vault);

        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, vaultBal, "wantBalanceFinal > vaultBal");
        assertEq(vault.balance(), vaultBal - wantBalanceFinal, "vaultBal != vaultBal - wantBalanceFinal");
    }

    function test_harvest() external override {
        uint wantBalBefore = want.balanceOf(address(user));
        _depositIntoVault(user, wantAmount);
        uint vaultBalance = vault.balance();
        assertGe(vaultBalance + 1, wantAmount, "Vault balance < wantAmount");

        bool stratHoldsWant = strategy.balanceOfPool() == 0;
        uint pps = vault.getPricePerFullShare();
        uint lastHarvest = strategy.lastHarvest();

        skip(delay);
        beforeHarvest();
        console.log("Harvesting vault");
        strategy.harvest();

        // in case of lockedProfit harvested balance is not available right away
        skip(delay);

        uint256 vaultBalAfterHarvest = vault.balance();
        uint256 ppsAfterHarvest = vault.getPricePerFullShare();
        uint256 lastHarvestAfterHarvest = strategy.lastHarvest();
        assertGt(vaultBalAfterHarvest, vaultBalance, "Harvested 0");
        assertGt(ppsAfterHarvest, pps, "Expected ppsAfterHarvest > initial");
        assertGt(lastHarvestAfterHarvest, lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");

        console.log("Withdraw all");
        user.withdrawAll(vault);
        uint wantBalAfterWithdrawal = want.balanceOf(address(user));
        console.log("User want balance", wantBalAfterWithdrawal);
        assertLe(wantBalAfterWithdrawal, vaultBalAfterHarvest, "wantBalAfterWithdrawal too big");
        assertGt(wantBalAfterWithdrawal, wantBalBefore * 99 / 100, "wantBalAfterWithdrawal too small");

        console.log("Deposit all");
        user.depositAll(vault);
        uint wantBalFinal = want.balanceOf(address(user));
        uint vaultBalFinal = vault.balance();
        uint balOfPoolFinal = strategy.balanceOfPool();
        uint balOfWantFinal = strategy.balanceOfWant();
        assertEq(wantBalFinal, 0, "wantBalFinal != 0");
        assertGt(vaultBalFinal, vaultBalAfterHarvest * 99 / 100, "vaultBalFinal != vaultBalAfterHarvest");

        // strategy holds want without depositing into farming pool
        if (stratHoldsWant) {
            assertEq(balOfPoolFinal, 0, "balOfPoolFinal != 0");
            assertEq(balOfWantFinal, vaultBalFinal, "balOfWantFinal != vaultBalFinal");
        } else {
            assertEq(balOfPoolFinal, vaultBalFinal, "balOfPoolFinal != vaultBalFinal");
            assertEq(balOfWantFinal, 0, "balOfWantFinal != 0");
        }
    }

}