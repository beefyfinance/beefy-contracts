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
    uint256 slot; // Storage slot that holds `balanceOf` mapping.
    bool slotSet;
    // Input amount of test want.
    uint256 wantStartingAmount = 50 ether;
    uint256 delay = 1000 seconds; // Time to wait after depositing before harvesting.


    function setUp() public {
        want = IERC20Like(vault.want());
        strategy = IStrategyComplete(vault.strategy());
        
        user = new VaultUser();

        // Slot set is for performance speed up.
        if (slotSet) {
            modifyBalanceWithKnownSlot(vault.want(), address(user), wantStartingAmount, slot);
        } else {
            slot = modifyBalance(vault.want(), address(user), wantStartingAmount);
            slotSet = true;
        }
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

    function test_panic() external {
        _unpauseIfPaused();
        
        _depositIntoVault();

        uint256 vaultBalance = vault.balance();
        uint256 balanceOfPool = strategy.balanceOfPool();
        uint256 balanceOfWant = strategy.balanceOfWant();

        assertTrue(balanceOfPool > balanceOfWant);
        
        console.log("Calling panic()");
        FORGE_VM.prank(keeper);
        strategy.panic();

        uint256 vaultBalanceAfterPanic = vault.balance();
        uint256 balanceOfPoolAfterPanic = strategy.balanceOfPool();
        uint256 balanceOfWantAfterPanic = strategy.balanceOfWant();

        assertTrue(vaultBalanceAfterPanic > vaultBalance  * 99 / 100, "Expected vaultBalanceAfterPanic > vaultBalance");
        assertTrue(balanceOfWantAfterPanic > balanceOfPoolAfterPanic, "Expected balanceOfWantAfterPanic > balanceOfPoolAfterPanic");

        console.log("Getting user more want.");
        modifyBalanceWithKnownSlot(vault.want(), address(user), wantStartingAmount, slot);
        console.log("Approving more want.");
        user.approve(address(want), address(vault), wantStartingAmount);
        
        // Users can't deposit.
        console.log("Trying to deposit while panicked.");
        FORGE_VM.expectRevert("Pausable: paused");
        user.depositAll(vault);
        
        // User can still withdraw
        console.log("User withdraws all.");
        user.withdrawAll(vault);
        
        uint256 wantBalanceFinal = want.balanceOf(address(user));
        assertTrue(wantBalanceFinal > wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
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