// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import {BaseTestHarness, console} from "./utils/BaseTestHarness.sol";

// Contracts
import {BeefyVaultV6} from "../vaults/BeefyVaultV6.sol";
import {StrategyCommonChefLP} from "../strategies/Common/StrategyCommonChefLP.sol";

// Interfaces
import {IBeefyVaultV6} from "../interfaces/beefy/IBeefyVaultV6.sol";
import {IStrategyComplete} from "../interfaces/beefy/IStrategyComplete.sol";
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

    IERC20Like want;
    uint256 wantStartingAmount = 1 ether;

    function setup() external {
        want = IERC20Like(vault.want());
        strategy = IStrategyComplete(vault.strategy());
        
        user = new VaultUser();
        modifyBalance(vault.want(), wantStartingAmount, address(user));
    }

    function test_depositAndWithdraw() external {
        _unpauseIfPaused();

        console.log("Approving want spend.");
        user.approve(address(want), address(vault), wantStartingAmount);
        console.log("Depositing all want into vault", wantStartingAmount);
        user.depositAll(vault);
        
        shift(100 seconds);

        console.log("Withdrawing all want from vault");
        user.withdrawAll(vault);

        uint256 wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertTrue(wantBalanceFinal <= wantStartingAmount);
        assertTrue(wantBalanceFinal > wantStartingAmount * 99 / 100);
    }

    /*         */
    /* Helpers */
    /*         */

    function _unpauseIfPaused() internal {
        if (strategy.paused()) {
            console.log("Unpausing vault.");
            FORGE_VM.prank(keeper);
            strategy.unpause();
        }
    }
}