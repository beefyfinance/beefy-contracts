// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeFactoryTest.t.sol";
import "../../../contracts/BIFI/strategies/Pendle/StrategyPendle.sol";

contract StrategyPendleTest is BaseAllToNativeFactoryTest {

    StrategyPendle strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyPendle();
        else strategy = StrategyPendle(payable(_impl));
        cacheOraclePrices();
        return address(strategy);
    }

    function beforeHarvest() internal override {
        vm.roll(block.number + 1); // pass lastRewardBlock check in PendleMarket
        strategy.claim();
    }

    // custom test as balanceOfPool is always 0 as strat simply holds want
    function test_depositAndWithdraw() public override {
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
        address capsOracle = 0xcD7f45566bc0E7303fB92A93969BB4D3f6e662bb;
        if (capsOracle.code.length > 0) {
            bytes memory callData = abi.encodeWithSignature("getPrice(address)", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
            (, bytes memory resData) = capsOracle.staticcall(callData);
            vm.mockCall(capsOracle, callData, resData);

            callData = abi.encodeWithSignature("getPrice(address)", 0xcCcc62962d17b8914c62D74FfB843d73B2a3cccC);
            (,resData) = capsOracle.staticcall(callData);
            vm.mockCall(capsOracle, callData, resData);
        }
    }
}