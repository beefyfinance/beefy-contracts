// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import {BaseTestHarness} from "./utils/BaseTestHarness.sol";

// Contracts
import {BeefyVaultV6} from "../BIFI/vaults/BeefyVaultV6.sol";
import {StrategyCommonChefLP} from "../BIFI/strategies/Common/StrategyCommonChefLP.sol";

// Interfaces
import {IBeefyVaultV6} from "../BIFI/interfaces/beefy/IBeefyVaultV6.sol";
import {IStrategyComplete} from "../BIFI/interfaces/beefy/IStrategyComplete.sol";
import {IERC20Like} from "./interfaces/IERC20Like.sol";

// Users
import {VaultUser} from "./users/VaultUser.sol";

contract ProdVaultTest is BaseTestHarness {

    // Input your vault to test here.
    IBeefyVaultV6 constant vault = IBeefyVaultV6(0x1313b9C550bbDF55Fc06f63a41D8BDC719d056A6);
    IStrategyComplete strategy;

    // Users
    VaultUser user;
    address constant keeper = 0x10aee6B5594942433e7Fc2783598c979B030eF3D;

    uint256 wantStartingAmount = 1 ether;

    function setup() external {
        strategy = IStrategyComplete(vault.strategy());
        
        user = new VaultUser();
        modifyBalance(vault.want(), wantStartingAmount, address(user));
    }

    function test_depositAndWithdraw() external {
        _unpauseIfPaused();

        user.approve(vault.want(), address(vault), wantStartingAmount);
        user.depositAll(vault);
        
        shift(100 seconds);

        user.withdrawAll(vault);

        uint256 wantBalanceFinal = IERC20Like(vault.want()).balanceOf(address(user));
        assertTrue(wantBalanceFinal <= wantStartingAmount);
        assertTrue(wantBalanceFinal > wantStartingAmount * 99 / 100);
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