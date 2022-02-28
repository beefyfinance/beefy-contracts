// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import {BaseTestHarness} from "../forgeLib/BaseTestHarness.sol";

// Contracts
import {BeefyVaultV6} from "../../contracts/BIFI/vaults/BeefyVaultV6.sol";
import {StrategyCommonChefLP} from "../../contracts/BIFI/strategies/Common/StrategyCommonChefLP.sol";

// Interfaces
import {IBeefyVaultV6} from "../../contracts/BIFI/interfaces/beefy/IBeefyVaultV6.sol";
import {IStrategyComplete} from "../../contracts/BIFI/interfaces/beefy/IStrategyComplete.sol";

// Users
import {VaultUser} from "../forgeLib/VaultUser.sol";

contract ProdVaultTest is BaseTestHarness {

    // Input your vault to test here.
    IBeefyVaultV6 constant vault = IBeefyVaultV6(0x1313b9C550bbDF55Fc06f63a41D8BDC719d056A6);
    IStrategyComplete strategy;

    // Users
    VaultUser user;
    address constant keeper = 0x10aee6B5594942433e7Fc2783598c979B030eF3D;

    uint256 wantAmount = 1 ether;

    function setup() external {
        strategy = IStrategyComplete(vault.strategy());
        
        user = new VaultUser();
        modifyBalance(vault.want(), wantAmount, address(user));
    }

    function test_depositAndWithdraw() external {
        _unpauseIfPaused();
    }

    /*         */
    /* Helpers */
    /*         */

    function _unpauseIfPaused() internal {
        if (strategy.paused()) {
            FORGE_VM.prank(keeper);
            strategy.unpause();
        }
    }
}