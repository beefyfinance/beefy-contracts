// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../node_modules/forge-std/src/Test.sol";

import "../users/VaultUser.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IERC20Like.sol";
import "../utils/Utils.sol";
import {StrategyFactory} from "../../../contracts/BIFI/infra/StrategyFactory.sol";
import {BaseAllToNativeFactoryStrat} from "../../../contracts/BIFI/strategies/Common/BaseAllToNativeFactoryStrat.sol";

contract FactoryUpgrade is Test {

    uint256 wantAmount = 5000000 ether;

    IVault vault;
    BaseAllToNativeFactoryStrat strategy;
    VaultUser user;

    string stratName;
    address newImpl;
    StrategyFactory factory;

    function setUp() public {
        address strat = vm.envAddress("STRAT");
        newImpl = vm.envAddress("NEW_IMPL");
        strategy = BaseAllToNativeFactoryStrat(payable(strat));
        factory = StrategyFactory(address(strategy.factory()));
        stratName = strategy.stratName();
        vault = IVault(strategy.vault());
        console.log(vault.name(), vault.symbol());
        user = new VaultUser();
        deal(vault.want(), address(user), wantAmount);
    }

    function test_upgrade() external {
        uint vaultBalance = vault.balance();
        uint pps = vault.getPricePerFullShare();

        console.log("Upgrade strat");
        vm.prank(factory.owner());
        factory.upgradeTo(stratName, newImpl);
        assertEq(newImpl, factory.getImplementation(stratName), "!upgraded");

        if (strategy.paused()) {
            vm.prank(strategy.keeper());
            strategy.unpause();
        }

        skip(1 days);
        console.log("Harvest");
        strategy.harvest();
        skip(1 days);
        uint256 vaultBalAfterHarvest = vault.balance();
        uint256 ppsAfterHarvest = vault.getPricePerFullShare();
        console.log("Balance", vaultBalance, vaultBalAfterHarvest);
        console.log("PPS", pps, ppsAfterHarvest);
        assertGt(vaultBalAfterHarvest, vaultBalance, "Harvested 0");
        assertGt(ppsAfterHarvest, pps, "Expected ppsAfterHarvest > initial");

        console.log("Panic");
        vm.prank(strategy.keeper());
        strategy.panic();

        console.log("Unpause");
        vm.prank(strategy.keeper());
        strategy.unpause();

        console.log("Deposit");
        user.approve(vault.want(), address(vault), wantAmount);
        user.depositAll(vault);

        console.log("Withdrawal");
        user.withdrawAll(vault);
        uint userBal = IERC20Like(vault.want()).balanceOf(address(user));
        console.log("User balance after withdrawal", userBal);
        assertGt(userBal, wantAmount * 99 / 100, "Expected balance increase");
    }

    function test_printCalls() public view {
        bytes memory callData = abi.encodeCall(StrategyFactory.upgradeTo, (stratName, newImpl));
        console.log("owner:", factory.owner());

        console.log("\nUpgrade:");
        console.log("target:", address(factory));
        console.log("data:", Utils.bytesToStr(callData));
    }
}