// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "forge-std/Test.sol";

// Users
import {VaultUser} from "forge/test/users/VaultUser.sol";
// Interfaces
import {IERC20Like} from "forge/test/interfaces/IERC20Like.sol";
import {IVault} from "forge/test/interfaces/IVault.sol";
import {BaseTestHarness} from "forge/test/utils/BaseTestHarness.sol";
import {IStrategy} from "forge/test/interfaces/IStrategy.sol";
import {StratFeeManager, StrategyLLCurveLP} from "contracts/BIFI/strategies/StakeDAO/StrategyLLCurveLP.sol";


interface ILocker {
    function claim(address _token) external;
}

contract StrategyLLCurveLPTest is Test {

    address internal constant _SD_STRATEGY = 0x2B82FB2B4bac16a1188f377D6a913f235715031b;

    address sdLocker = 0x2B82FB2B4bac16a1188f377D6a913f235715031b;
    address sdMultisig = 0xfDB1157ac847D334b8912df1cd24a93Ee22ff3d0;
    address beefyFeeConfig = 0xDC1dC2abC8775561A6065D0EE27E8fDCa8c4f7ED;

    address internal crv = 0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978;
    address internal weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address internal usdt = 0x337610d27c682E347C9cD60BD4b3b107C9d34dDd;

    // Main params.
    IERC20Like internal want = IERC20Like(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
    address internal gauge = 0xCE5F24B7A95e9cBa7df4B54E911B4A3Dc8CDAf6f;
    address internal sdVault = 0x0f958528718b625c3aebd305dd2917a37570C56a;
    address internal liquidityGauge = 0x044f4954937316db6502638065b95E921Fd28475;

    // Current setup in prod.
    // USDC/USDT Vault.
    IVault constant vault = IVault(0xEc7c0205a6f426c2Cb1667d783B5B4fD2f875434);
    IStrategy OldStrategy;

    // New strategy.
    StrategyLLCurveLP strategy;

    // Users
    VaultUser user;

    // Common
    uint256 slot; // Storage slot that holds `balanceOf` mapping.
    bool slotSet;
    // Input amount of test want.
    uint256 wantStartingAmount = 50 ether;
    uint256 delay = 1000 seconds; // Time to wait after depositing before harvesting.

    address internal keeper;
    address internal vaultOwner;
    address internal strategyOwner; // fantom

    function setUp() public {
        OldStrategy = IStrategy(vault.strategy());

        keeper = OldStrategy.keeper();
        vaultOwner = vault.owner();
        strategyOwner = OldStrategy.owner();

        StratFeeManager.CommonAddresses memory commonAddresses = StratFeeManager.CommonAddresses({
            vault: address(vault),
            unirouter: OldStrategy.unirouter(),
            keeper: OldStrategy.keeper(),
            strategist: sdMultisig,
            beefyFeeRecipient: OldStrategy.beefyFeeRecipient(),
            beefyFeeConfig: beefyFeeConfig
        });

        uint256[] memory params = new uint256[](4);
        params[0] = 2;
        params[1] = 0;
        params[2] = 0;
        params[3] = 0;

        address[] memory crvToNative = new address[](2);
        crvToNative[0] = crv;
        crvToNative[1] = weth;

        address[] memory nativeToUsdc = new address[](2);
        nativeToUsdc[0] = weth;
        nativeToUsdc[1] = usdc;

        // Deploy new strategy.
        strategy = new StrategyLLCurveLP(
            address(want),
            gauge,
            address(want),
            sdVault,
            liquidityGauge,
            _SD_STRATEGY,
            params,
            crvToNative,
            nativeToUsdc,
            commonAddresses
        );

        uint256 _before = OldStrategy.balanceOfPool();

        // Migrage strategy.
        vm.startPrank(vault.owner());
        vault.proposeStrat(address(strategy));
        skip(vault.approvalDelay() + 1);
        vault.upgradeStrat();
        vm.stopPrank();

        assertEq(strategy.balanceOfPool(), _before);

        // Set up user.
        user = new VaultUser();
        deal(vault.want(), address(user), wantStartingAmount);
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
        assertGt(
            wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100"
        );
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

        assertGe(
            pricePerFullShareAfterUser2Deposit,
            pricePerFullShare,
            "Expected pricePerFullShareAfterUser2Deposit >= pricePerFullShare"
        );
        assertGe(
            pricePerFullShareAfterUser1Withdraw,
            pricePerFullShareAfterUser2Deposit,
            "Expected pricePerFullShareAfterUser1Withdraw >= pricePerFullShareAfterUser2Deposit"
        );
        assertGt(
            user1WantBalanceFinal,
            wantStartingAmount * 99 / 100,
            "Expected user1WantBalanceFinal > wantStartingAmount * 99 / 100"
        );
    }

    function test_harvest() external {
        _unpauseIfPaused();

        _depositIntoVault(user);

        uint256 vaultBalance = vault.balance();
        uint256 pricePerFullShare = vault.getPricePerFullShare();
        uint256 lastHarvest = strategy.lastHarvest();

        uint256 timestampBeforeHarvest = block.timestamp;
        skip(delay);

        /// Simulate Lockers Claim.
        ILocker(sdLocker).claim(address(want));

        // Skip couple times because of the reward distribution period.
        // Rewards are distributed over 7 days.
        skip(3.5 days);

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
        assertGt(
            pricePerFullShareAfterHarvest,
            pricePerFullShare,
            "Expected pricePerFullShareAfterHarvest > pricePerFullShare"
        );
        assertGt(
            wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100"
        );
        assertGt(lastHarvestAfterHarvest, lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");
        assertEq(
            lastHarvestAfterHarvest,
            timestampBeforeHarvest + delay + 3.5 days,
            "Expected lastHarvestAfterHarvest == timestampBeforeHarvest + delay"
        );
    }

    function test_panic() external {
        _unpauseIfPaused();

        _depositIntoVault(user);

        uint256 vaultBalance = vault.balance();
        uint256 balanceOfPool = strategy.balanceOfPool();
        uint256 balanceOfWant = strategy.balanceOfWant();

        assertGt(balanceOfPool, balanceOfWant);

        console.log("Calling panic()");
        vm.prank(keeper);
        strategy.panic();

        uint256 vaultBalanceAfterPanic = vault.balance();
        uint256 balanceOfPoolAfterPanic = strategy.balanceOfPool();
        uint256 balanceOfWantAfterPanic = strategy.balanceOfWant();

        assertGt(vaultBalanceAfterPanic, vaultBalance * 99 / 100, "Expected vaultBalanceAfterPanic > vaultBalance");
        assertGt(
            balanceOfWantAfterPanic,
            balanceOfPoolAfterPanic,
            "Expected balanceOfWantAfterPanic > balanceOfPoolAfterPanic"
        );

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
        assertGt(
            wantBalanceFinal, wantStartingAmount * 99 / 100, "Expected wantBalanceFinal > wantStartingAmount * 99 / 100"
        );
    }

    /*         */
    /* Helpers */
    /*         */

    function _unpauseIfPaused() internal {
        if (strategy.paused()) {
            console.log("Unpausing vault.");
            vm.prank(keeper);
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
