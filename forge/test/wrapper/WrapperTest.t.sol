// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {BaseTestHarness} from "../utils/BaseTestHarness.sol";
import "forge-std/Test.sol";

// Interfaces
import {IVault} from "../interfaces/IVault.sol";
import {IWrapper} from "../interfaces/IWrapper.sol";
import {IWrapperFactory} from "../interfaces/IWrapperFactory.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IERC20Like} from "../interfaces/IERC20Like.sol";

// Users
import {WrapperUser} from "../users/WrapperUser.sol";

contract WrapperTest is BaseTestHarness {

    // Input your vault to test here.
    IWrapperFactory factory = IWrapperFactory(0x48bF3a071098a09C7D00379b4DBC69Ab6Da83a36); 
    IVault constant vault = IVault(0xf6a1284Dc2ce247Bca885ac4F36b37E91d3bD032); // Moo Hop ETH on Arbitrum
    IWrapper wrapper;
    IStrategy strategy;

    // Users
    WrapperUser user;
    address constant keeper = 0x4fED5491693007f0CD49f4614FFC38Ab6A04B619;
    address constant vaultOwner = 0x9A94784264AaAE397441c1e47fA132BE4e61BdaD;
    address constant strategyOwner = 0x6d28afD25a1FBC5409B1BeFFf6AEfEEe2902D89F;

    IERC20Like want;
    uint256 slot; // Storage slot that holds `balanceOf` mapping.
    bool slotSet;
    // Input amount of test want.
    uint256 wantStartingAmount = 50 ether;
    uint256 delay = 1000 seconds; // Time to wait after depositing before harvesting.


    function setUp() public {
        wrapper = IWrapper(factory.clone(address(vault)));

        want = IERC20Like(wrapper.asset());
        strategy = IStrategy(vault.strategy());
        
        user = new WrapperUser();

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

        uint256 shareEstimate = wrapper.previewDeposit(want.balanceOf(address(user)));
        _depositIntoWrapper(user);
        uint256 shares = wrapper.balanceOf(address(user));
        
        shift(100 seconds);

        console.log("Withdrawing all want from vault");
        uint256 withdrawEstimate = wrapper.previewRedeem(wrapper.balanceOf(address(user)));
        user.withdrawAll(wrapper);

        uint256 wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertGt(shares, shareEstimate * 99 / 100, "Minted shares > estimated shares * 99 / 100");
        assertGt(wantBalanceFinal, withdrawEstimate * 99 / 100, "Expected wantBalanceFinal > withdrawEstimate * 99 / 100");
        assertLe(wantBalanceFinal, wantStartingAmount, "Expected wantBalanceFinal <= wantStartingAmount");
        assertGt(wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
    }

    function test_unwrapAndWrap() external {
        _unpauseIfPaused();

        _depositIntoWrapper(user);
        uint256 wrapperBalance = wrapper.balanceOf(address(user));

        console.log("Unwrapping all mooTokens from wrapper");
        user.unwrapAll(wrapper);

        uint256 vaultBalance = vault.balanceOf(address(user));
        
        shift(100 seconds);

        console.log("Wrapping all mooTokens");
        user.approve(address(vault), address(wrapper), vaultBalance);
        user.wrapAll(wrapper);
        uint256 wrapperBalanceFinal = wrapper.balanceOf(address(user));

        assertEq(wrapperBalance, vaultBalance, "Unwrapping 1:1");
        assertEq(wrapperBalanceFinal, vaultBalance, "Wrapping 1:1");
    }

    function test_harvest() external {
        _unpauseIfPaused();
        
        _depositIntoWrapper(user);

        uint256 vaultBalance = wrapper.totalAssets();
        uint256 pricePerFullShare = vaultBalance * 1e18 / wrapper.totalSupply();
        uint256 lastHarvest = strategy.lastHarvest();

        uint256 timestampBeforeHarvest = block.timestamp;
        shift(delay);

        console.log("Testing call rewards > 0");
        uint256 callRewards = strategy.callReward();
        assertGt(callRewards, 0, "Expected callRewards > 0");

        console.log("Harvesting vault.");
        bool didHarvest = _harvest();
        assertTrue(didHarvest, "Harvest failed.");

        uint256 vaultBalanceAfterHarvest = wrapper.totalAssets();
        uint256 pricePerFullShareAfterHarvest = vaultBalanceAfterHarvest * 1e18 / wrapper.totalSupply();
        uint256 lastHarvestAfterHarvest = strategy.lastHarvest();

        console.log("Withdrawing all want.");
        user.withdrawAll(wrapper);

        uint256 wantBalanceFinal = want.balanceOf(address(user));

        assertGt(vaultBalanceAfterHarvest, vaultBalance, "Expected vaultBalanceAfterHarvest > vaultBalance");
        assertGt(pricePerFullShareAfterHarvest, pricePerFullShare, "Expected pricePerFullShareAfterHarvest > pricePerFullShare");
        assertGt(wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
        assertGt(lastHarvestAfterHarvest, lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");
        assertEq(lastHarvestAfterHarvest, timestampBeforeHarvest + delay, "Expected lastHarvestAfterHarvest == timestampBeforeHarvest + delay");
    }

    function test_panic() external {
        _unpauseIfPaused();
        
        _depositIntoWrapper(user);

        uint256 vaultBalance = wrapper.totalAssets();
        uint256 balanceOfPool = strategy.balanceOfPool();
        uint256 balanceOfWant = strategy.balanceOfWant();

        assertGt(balanceOfPool, balanceOfWant);
        
        console.log("Calling panic()");
        FORGE_VM.prank(keeper);
        strategy.panic();

        uint256 vaultBalanceAfterPanic = wrapper.totalAssets();
        uint256 balanceOfPoolAfterPanic = strategy.balanceOfPool();
        uint256 balanceOfWantAfterPanic = strategy.balanceOfWant();

        assertGt(vaultBalanceAfterPanic, vaultBalance  * 99 / 100, "Expected vaultBalanceAfterPanic > vaultBalance");
        assertGt(balanceOfWantAfterPanic, balanceOfPoolAfterPanic, "Expected balanceOfWantAfterPanic > balanceOfPoolAfterPanic");

        console.log("Getting user more want.");
        modifyBalanceWithKnownSlot(vault.want(), address(user), wantStartingAmount, slot);
        console.log("Approving more want.");
        user.approve(address(want), address(wrapper), wantStartingAmount);
        
        // Users can't deposit.
        console.log("Trying to deposit while panicked.");
        FORGE_VM.expectRevert("Pausable: paused");
        user.depositAll(wrapper);
        
        // User can still withdraw
        console.log("User withdraws all.");
        user.withdrawAll(wrapper);

        uint256 wantBalanceFinal = want.balanceOf(address(user));
        assertGt(wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100");
    }

    function test_multipleUsers() external {
        _unpauseIfPaused();
        
        _depositIntoWrapper(user);

        // Setup second user.
        WrapperUser user2 = new WrapperUser();
        console.log("Getting want for user2.");
        modifyBalanceWithKnownSlot(address(want), address(user2), wantStartingAmount, slot);

        uint256 pricePerFullShare = wrapper.totalAssets() * 1e18 / wrapper.totalSupply();

        shift(delay);

        console.log("User2 depositAll.");
        _depositIntoWrapper(user2);
        
        uint256 pricePerFullShareAfterUser2Deposit = wrapper.totalAssets() * 1e18 / wrapper.totalSupply();

        shift(delay);

        console.log("User1 withdrawAll.");
        user.withdrawAll(wrapper);

        uint256 user1WantBalanceFinal = want.balanceOf(address(user));
        uint256 pricePerFullShareAfterUser1Withdraw = wrapper.totalAssets() * 1e18 / wrapper.totalSupply();

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
            assertEq(strategy.withdrawFee(), 0, "Vault is harvestOnDeposit but has withdrawal fee.");
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

    function _depositIntoWrapper(WrapperUser user_) internal {
        console.log("Approving want spend.");
        user_.approve(address(want), address(wrapper), wantStartingAmount);
        console.log("Depositing all want into vault", wantStartingAmount);
        user_.depositAll(wrapper);
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