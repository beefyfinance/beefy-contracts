// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../utils/Utils.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCallTest is BaseStrategyTest {

    bytes data;
    IStrategy strategy;

    function createStrategy(address) internal override returns (address) {
        address _strat = vm.envAddress("STRAT");
        strategy = IStrategy(_strat);
        IVault vault = IVault(strategy.vault());
        console.log(vault.name(), vault.symbol());

        data = vm.envBytes("DATA");
        vm.prank(strategy.owner());
        (bool success,) = _strat.call(data);
        assertTrue(success, "Strategy call not success");

        return _strat;
    }

    function test_printCalls() public view {
        console.log("owner:", strategy.owner());

        console.log("\nCall:");
        console.log("target:", address(strategy));
        console.log("data:", Utils.bytesToStr(data));
    }
}