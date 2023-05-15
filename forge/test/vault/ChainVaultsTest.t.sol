// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import { Test, console } from "forge-std/Test.sol";
import { HardhatNetworkManager } from "./util/HardhatNetworkManager.sol";
import { AddressBook } from "./util/AddressBook.sol";

// Interfaces
import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IERC20Like} from "../interfaces/IERC20Like.sol";

// Users
import {VaultUser} from "../users/VaultUser.sol";

contract ChainVaultsTest is Test {

    // Input your vault to test here.
    IVault vault;
    IStrategy strategy;

    // Users
    VaultUser user;
    IERC20Like want;
    
    // Input amount of test want.
    uint256 wantStartingAmount = 50 ether;
    // Time to wait after depositing before harvesting.
    uint256 delay = 1000 seconds;

    // address book data
    AddressBook.BeefyPlatform addressBookBeefy;

    function setUp() public {
        // configure test from environment
        string memory chain = vm.envString("CHAIN");
        require(bytes(chain).length > 0, "Set the 'CHAIN' environment variable with any chain name");
        address vaultAddress = vm.envAddress("VAULT");
        require(vaultAddress != address(0x0), "Set the 'VAULT' environment variable with the vault address to test");
        uint256 blockNumber = vm.envOr("BLOCK", uint256(0));

        // initialize fork based on our hardhat network config and the requested chain
        HardhatNetworkManager net = new HardhatNetworkManager();
        if (blockNumber > 0) net.createHardhatNetworkFork(chain, blockNumber);
        else net.createHardhatNetworkFork(chain);

        // setup various infos
        vault = IVault(vaultAddress);
        want = IERC20Like(vault.want());
        strategy = IStrategy(vault.strategy());
        user = new VaultUser();

        // reset the user balance of want
        deal(vault.want(), address(user), wantStartingAmount);

        // load the addressbook
        AddressBook ab = new AddressBook();
        addressBookBeefy = ab.getBeefyPlatformConfig(chain);
    }

    function test_depositAndWithdraw() external {
        _unpauseIfPaused();
        _depositIntoVault(user);
        
        skip(100 seconds);

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
        skip(delay);

//        console.log("Testing call rewards > 0");
//        uint256 callRewards = strategy.callReward();
//        assertGt(callRewards, 0, "Expected callRewards > 0");

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
        vm.prank(addressBookBeefy.keeper);
        strategy.panic();

        uint256 vaultBalanceAfterPanic = vault.balance();
        uint256 balanceOfPoolAfterPanic = strategy.balanceOfPool();
        uint256 balanceOfWantAfterPanic = strategy.balanceOfWant();

        assertGt(vaultBalanceAfterPanic, vaultBalance  * 99 / 100, "Expected vaultBalanceAfterPanic > vaultBalance");
        assertGt(balanceOfWantAfterPanic, balanceOfPoolAfterPanic, "Expected balanceOfWantAfterPanic > balanceOfPoolAfterPanic");

        console.log("Getting user more want.");
        deal(vault.want(), address(user), wantStartingAmount);
        console.log("Approving more want.");
        user.approve(address(want), address(vault), wantStartingAmount);
        
        // Users can't deposit.
        console.log("Trying to deposit while panicked.");
        vm.expectRevert("Pausable: paused");
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
        deal(address(want), address(user2), wantStartingAmount);

        uint256 pricePerFullShare = vault.getPricePerFullShare();

        skip(delay);

        console.log("User2 depositAll.");
        _depositIntoVault(user2);
        
        uint256 pricePerFullShareAfterUser2Deposit = vault.getPricePerFullShare();

        skip(delay);

        console.log("User1 withdrawAll.");
        user.withdrawAll(vault);

        uint256 user1WantBalanceFinal = want.balanceOf(address(user));
        uint256 pricePerFullShareAfterUser1Withdraw = vault.getPricePerFullShare();

        assertGe(pricePerFullShareAfterUser2Deposit, pricePerFullShare, "Expected pricePerFullShareAfterUser2Deposit >= pricePerFullShare");
        assertGe(pricePerFullShareAfterUser1Withdraw, pricePerFullShareAfterUser2Deposit, "Expected pricePerFullShareAfterUser1Withdraw >= pricePerFullShareAfterUser2Deposit");
        assertGt(user1WantBalanceFinal, wantStartingAmount * 99 / 100, "Expected user1WantBalanceFinal > wantStartingAmount * 99 / 100");
    }

    function test_correctOwnerAndKeeper() external {
        assertEq(vault.owner(), addressBookBeefy.vaultOwner, "Wrong vault owner.");
        assertEq(strategy.owner(), addressBookBeefy.strategyOwner, "Wrong strategy owner.");
        assertEq(strategy.keeper(), addressBookBeefy.keeper, "Wrong keeper.");
    }

    function test_harvestOnDeposit() external {
        bool harvestOnDeposit = strategy.harvestOnDeposit();
        if (harvestOnDeposit) {
            console.log("Vault is harvestOnDeposit.");
            assertEq(strategy.withdrawFee(), 0, "Vault is harvestOnDeposit but has withdrawal fee.");
        } else {
            console.log("Vault is NOT harvestOnDeposit.");
            assertGt(strategy.withdrawFee(), 0, "Vault is not harvestOnDeposit but doesn't have withdrawal fee.");
        }
    }

    /*         */
    /* Helpers */
    /*         */

    function _unpauseIfPaused() internal {
        if (strategy.paused()) {
            console.log("Unpausing vault.");
            vm.prank(addressBookBeefy.keeper);
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
                skip(delay);
            }
        }
    }
}