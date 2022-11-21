// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {BaseTestHarness} from "./utils/BaseTestHarness.sol";
import "forge-std/Test.sol";

// Interfaces
import {IVault} from "./interfaces/IVault.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IERC20Like} from "./interfaces/IERC20Like.sol";

// Users
import {VaultUser} from "./users/VaultUser.sol";

contract ProdVaultTest is BaseTestHarness {

    // Input your vault to test here.
    IVault constant vault = IVault(0xc4f179b4096514c48ce70b9Ad27e689A3f2C9831);
    IStrategy strategy;

    // Users
    VaultUser user;
    address constant keeper = 0x340465d9D2EbDE78F15a3870884757584F97aBB4;
    address constant vaultOwner = 0xc8F3D9994bb1670F5f3d78eBaBC35FA8FdEEf8a2; // fantom
    address constant strategyOwner = 0xfcDD5a02C611ba6Fe2802f885281500EC95805d7; // fantom

    IERC20Like want;
    uint256 slot; // Storage slot that holds `balanceOf` mapping.
    bool slotSet;
    // Input amount of test want.
    uint256 wantStartingAmount = 50 ether;
    uint256 delay = 1000 seconds; // Time to wait after depositing before harvesting.


    function setUp() public {
        want = IERC20Like(vault.want());
        strategy = IStrategy(vault.strategy());
        
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

        _depositIntoVault(user);
        
        shift(100 seconds);

        console.log("Withdrawing all want from vault");
        user.withdrawAll(vault);

        uint256 wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, wantStartingAmount, "Expected wantBalanceFinal <= wantStartingAmount");
        assertGt(wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
    }

    function test_harvest() external {
        _unpauseIfPaused();
        
        _depositIntoVault(user);

        uint256 vaultBalance = vault.balance();
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        uint256 lastHarvest = strategy.lastHarvest();

        uint256 timestampBeforeHarvest = block.timestamp;
        shift(delay);

        console.log("Testing call rewards > 0");
        uint256 callRewards = strategy.callReward();
        assertGt(callRewards, 0, "Expected callRewards > 0");

        console.log("Harvesting vault.");
        bool didHarvest = _harvest();
        assertTrue(didHarvest, "Harvest failed.");

        uint256 vaultBalanceAfterHarvest = vault.balance();
        uint256 pricePerFullShareAfterHarvest = vault.getPricePerFullShare();
        uint256 lastHarvestAfterHarvest = strategy.lastHarvest();

        console.log("Withdrawing all want.");
        user.withdrawAll(vault);

        uint256 wantBalanceFinal = want.balanceOf(address(user));

        assertGt(vaultBalanceAfterHarvest, vaultBalance, "Expected vaultBalanceAfterHarvest > vaultBalance");
        assertGt(pricePerFullShareAfterHarvest, pricePerFullShare, "Expected pricePerFullShareAfterHarvest > pricePerFullShare");
        assertGt(wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
        assertGt(lastHarvestAfterHarvest, lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");
        assertEq(lastHarvestAfterHarvest, timestampBeforeHarvest + delay, "Expected lastHarvestAfterHarvest == timestampBeforeHarvest + delay");
    }

    function test_panic() external {
        _unpauseIfPaused();
        
        _depositIntoVault(user);

        uint256 vaultBalance = vault.balance();
        uint256 balanceOfPool = strategy.balanceOfPool();
        uint256 balanceOfWant = strategy.balanceOfWant();

        assertGt(balanceOfPool, balanceOfWant);
        
        console.log("Calling panic()");
        FORGE_VM.prank(keeper);
        strategy.panic();

        uint256 vaultBalanceAfterPanic = vault.balance();
        uint256 balanceOfPoolAfterPanic = strategy.balanceOfPool();
        uint256 balanceOfWantAfterPanic = strategy.balanceOfWant();

        assertGt(vaultBalanceAfterPanic, vaultBalance  * 99 / 100, "Expected vaultBalanceAfterPanic > vaultBalance");
        assertGt(balanceOfWantAfterPanic, balanceOfPoolAfterPanic, "Expected balanceOfWantAfterPanic > balanceOfPoolAfterPanic");

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
        assertGt(wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
    }

    function test_multipleUsers() external {
        _unpauseIfPaused();
        
        _depositIntoVault(user);

        // Setup second user.
        VaultUser user2 = new VaultUser();
        console.log("Getting want for user2.");
        modifyBalanceWithKnownSlot(address(want), address(user2), wantStartingAmount, slot);

        uint256 pricePerFullShare = vault.getPricePerFullShare();

        shift(delay);

        console.log("User2 depositAll.");
        _depositIntoVault(user2);
        
        uint256 pricePerFullShareAfterUser2Deposit = vault.getPricePerFullShare();

        shift(delay);

        console.log("User1 withdrawAll.");
        user.withdrawAll(vault);

        uint256 user1WantBalanceFinal = want.balanceOf(address(user));
        uint256 pricePerFullShareAfterUser1Withdraw = vault.getPricePerFullShare();

        assertGe(pricePerFullShareAfterUser2Deposit, pricePerFullShare, "Expected pricePerFullShareAfterUser2Deposit >= pricePerFullShare");
        assertGe(pricePerFullShareAfterUser1Withdraw, pricePerFullShareAfterUser2Deposit, "Expected pricePerFullShareAfterUser1Withdraw >= pricePerFullShareAfterUser2Deposit");
        assertGt(user1WantBalanceFinal, wantStartingAmount * 99 / 100, "Expected user1WantBalanceFinal > wantStartingAmount * 99 / 100");
    }

    function test_correctOwnerAndKeeper() external {
        assertEq(vault.owner(), vaultOwner, "Wrong vault owner.");
        assertEq(strategy.owner(), strategyOwner, "Wrong strategy owner.");
        assertEq(strategy.keeper(), keeper, "Wrong keeper.");
    }

    function test_harvestOnDeposit() external {
        bool harvestOnDeposit = strategy.harvestOnDeposit();
        if (harvestOnDeposit) {
            console.log("Vault is harvestOnDeposit.");
            assertEq(strategy.withdrawalFee(), 0, "Vault is harvestOnDeposit but has withdrawal fee.");
        } else {
            console.log("Vault is NOT harvestOnDeposit.");
            assertEq(strategy.keeper(), keeper, "Vault is not harvestOnDeposit but doesn't have withdrawal fee.");
        }
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

    function _depositIntoVault(VaultUser user_) internal {
        console.log("Approving want spend.");
        user_.approve(address(want), address(vault), wantStartingAmount);
        console.log("Depositing all want into vault", wantStartingAmount);
        user_.depositAll(vault);
    }

    function _harvest() internal returns (bool didHarvest_) {
        // Retry a few times
        uint256 retryTimes = 5;
        for (uint256 i = 0; i < retryTimes; i++) {
            try strategy.harvest(address(user)) {
                didHarvest_ = true;
                break;
            } catch Error(string memory reason) {
                console.log("Harvest failed with", reason);
            } catch Panic(uint256 errorCode) {
                console.log("Harvest panicked, failed with", errorCode);
            } catch (bytes memory) {
                console.log("Harvest failed.");
            }
            if (i != retryTimes - 1) {
                console.log("Trying harvest again.");
                shift(delay);
            }
        }
    }
}