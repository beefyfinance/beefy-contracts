// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/degens/StrategyPearlTrident.sol";
import "./BaseAllToNativeFactoryTest.t.sol";


contract StrategyPearlTridentTest is BaseAllToNativeFactoryTest {

    StrategyPearlTrident strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyPearlTrident();
        else strategy = StrategyPearlTrident(payable(_impl));
        return address(strategy);
    }

    function test_harvestRatio() external {
        _depositIntoVault(user, wantAmount);
        uint vaultBalance = vault.balance();

        skip(1 days);
        console.log("Harvesting vault");
        vm.prank(strategy.keeper());
        strategy.setFastQuote(false);
        strategy.harvest();
        assertGt(vault.balance(), vaultBalance, "Harvested 0");
        console.log("lp0 balance", IERC20(strategy.lpToken0()).balanceOf(address(strategy)));
        console.log("lp1 balance", IERC20(strategy.lpToken1()).balanceOf(address(strategy)));
    }

    function test_harvestRatioFastQuote() external {
        _depositIntoVault(user, wantAmount);
        uint vaultBalance = vault.balance();

        skip(1 days);
        console.log("Harvesting vault");
        vm.prank(strategy.keeper());
        strategy.setFastQuote(true);
        strategy.harvest();
        assertGt(vault.balance(), vaultBalance, "Harvested 0");
        console.log("lp0 balance", IERC20(strategy.lpToken0()).balanceOf(address(strategy)));
        console.log("lp1 balance", IERC20(strategy.lpToken1()).balanceOf(address(strategy)));
    }

}