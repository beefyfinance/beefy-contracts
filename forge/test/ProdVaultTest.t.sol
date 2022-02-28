// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {BaseTestHarness, console} from "./utils/BaseTestHarness.sol";

// Interfaces
import {IBeefyVaultV6} from "./interfaces/IBeefyVaultV6.sol";
import {IStrategyComplete} from "./interfaces/IStrategyComplete.sol";
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
    uint256 wantStartingAmount = 100 ether;

    function setUp() public {
        console.log("Begin setup");
        want = IERC20Like(vault.want());
        console.log("strat", vault.strategy());
        strategy = IStrategyComplete(vault.strategy());
        
        user = new VaultUser();
        modifyBalance(vault.want(), address(user), wantStartingAmount);
        console.log("End setup");
    }

    function test_depositAndWithdraw() external {
        _unpauseIfPaused();

        _depositIntoVault();
        
        shift(100 seconds);

        console.log("Withdrawing all want from vault");
        user.withdrawAll(vault);

        uint256 wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertTrue(wantBalanceFinal <= wantStartingAmount, "Expected wantBalanceFinal <= wantStartingAmount");
        assertTrue(wantBalanceFinal > wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
    }

    function test_harvest() external {
        _unpauseIfPaused();
        
        _depositIntoVault();

        uint256 vaultBalance = vault.balance();
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        uint256 lastHarvest = strategy.lastHarvest();

        uint256 delay = 100 seconds;
        uint256 timestampBeforeHarvest = block.timestamp;
        shift(delay);

        console.log("Harvesting vault.");
        strategy.harvest(address(user));

        uint256 vaultBalanceAfterHarvest = vault.balance();
        uint256 pricePerFullShareAfterHarvest = vault.getPricePerFullShare();
        uint256 lastHarvestAfterHarvest = strategy.lastHarvest();

        console.log("Withdrawing all want.");
        user.withdrawAll(vault);

        uint256 wantBalanceFinal = want.balanceOf(address(user));

        assertTrue(vaultBalanceAfterHarvest > vaultBalance, "Expected vaultBalanceAfterHarvest > vaultBalance");
        assertTrue(pricePerFullShareAfterHarvest > pricePerFullShare, "Expected pricePerFullShareAfterHarvest > pricePerFullShare");
        assertTrue(wantBalanceFinal > wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
        assertTrue(lastHarvestAfterHarvest > lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");
        assertTrue(lastHarvestAfterHarvest == timestampBeforeHarvest + delay, "Expected lastHarvestAfterHarvest == timestampBeforeHarvest + delay");
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

    function _depositIntoVault() internal {
        console.log("Approving want spend.");
        user.approve(address(want), address(vault), wantStartingAmount);
        console.log("Depositing all want into vault", wantStartingAmount);
        user.depositAll(vault);
    }
}