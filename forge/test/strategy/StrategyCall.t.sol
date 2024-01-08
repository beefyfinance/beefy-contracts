// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "forge-std/Test.sol";
import "../../../node_modules/forge-std/src/Test.sol";

// Users
import "../users/VaultUser.sol";
// Interfaces
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IERC20Like.sol";
import "../utils/Utils.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyConvexStaking.sol";
import "../../../contracts/BIFI/strategies/Curve/CurveUniV3Adapter.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCallTest is BaseStrategyTest {

    uint256 wantAmount = 5000000 ether;

    IVault vault;
    IStrategy strategy;
    VaultUser user;

    bytes data;

    function setUp() public {
        address _strat = vm.envAddress("STRAT");
        strategy = IStrategy(_strat);
        vault = IVault(strategy.vault());
        console.log(vault.name(), vault.symbol());
        user = new VaultUser();

        data = vm.envBytes("DATA");
        vm.prank(strategy.owner());
        (bool success,) = _strat.call(data);
        assertTrue(success, "Strategy call not success");

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, strategy);
    }

    function test_printCalls() public view {
        console.log("owner:", strategy.owner());

        console.log("\nCall:");
        console.log("target:", address(strategy));
        console.log("data:", Utils.bytesToStr(data));
    }
}