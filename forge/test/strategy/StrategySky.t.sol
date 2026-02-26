// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Sky/StrategySky.sol";
import "./CommonBaseTest.t.sol";

contract StrategySkyTest is CommonBaseTest {

    function beforeHarvest() internal override {
        StrategySky strategy = StrategySky(payable(vault.strategy()));
        vm.prank(strategy.owner());
        strategy.addWantAsReward();
    }

    function test_selectFarm() public {
        StrategySky strategy = StrategySky(payable(vault.strategy()));
        address farm = strategy.currentFarm();
        address newFarm = 0x38E4254bD82ED5Ee97CD1C4278FAae748d998865;
        assertNotEq(farm, newFarm, "Same farm");

        console.log("Select new farm");
        vm.prank(strategy.keeper());
        strategy.selectFarm(newFarm);
        assertEq(strategy.currentFarm(), newFarm, "newFarm not selected");

        console.log("Select old farm");
        vm.prank(strategy.keeper());
        strategy.selectFarm(farm);
        assertEq(strategy.currentFarm(), farm, "Farm not selected");
    }
}