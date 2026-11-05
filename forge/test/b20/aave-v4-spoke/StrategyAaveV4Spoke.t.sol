// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {
    StrategyAaveV4Spoke,
    BaseAllToNativeFactoryStrat
} from "../../../../contracts/BIFI/strategies/Aave/StrategyAaveV4Spoke.sol";
import {StrategyFactory} from "../../../../contracts/BIFI/infra/StrategyFactory.sol";
import {BeefyVaultV7} from "../../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import {IStrategyV7} from "../../../../contracts/BIFI/interfaces/beefy/IStrategyV7.sol";
import {BeefyFeeConfigurator} from "../../../../contracts/BIFI/infra/BeefyFeeConfigurator.sol";
import "./Mocks.sol";

contract StrategyAaveV4SpokeTest is Test {
    StrategyAaveV4Spoke internal strategy;
    StrategyFactory internal factory;
    BeefyVaultV7 internal vault;
    MockToken internal want;
    MockToken internal native;
    MockToken internal reward;
    MockSpoke internal spoke;
    MockMerkl internal merkl;
    MockSwapper internal swapper;
    address internal user = address(0x111);
    address internal keeper = address(0x222);
    address internal treasury = address(0x333);
    address internal strategist = address(0x444);

    function setUp() public virtual {
        want = new MockToken(8);
        native = new MockToken(18);
        reward = new MockToken(6);
        spoke = new MockSpoke(address(want));
        merkl = new MockMerkl();
        swapper = new MockSwapper();
        swapper.setToken(address(want), 1e8);
        swapper.setToken(address(native), 1e18);
        swapper.setToken(address(reward), 1e6);
        want.mint(address(swapper), 1e18);
        native.mint(address(swapper), 1e28);
        BeefyFeeConfigurator fees = new BeefyFeeConfigurator();
        fees.initialize(keeper, 0.1e18);
        fees.setFeeCategory(0, 0.045e18, 0.1e18, 0.1e18, "test", true, false);
        factory = new StrategyFactory(address(native), keeper, treasury, address(fees));
        factory.addStrategy("AaveV4Spoke", address(new StrategyAaveV4Spoke()));
        vault = new BeefyVaultV7();
        strategy = StrategyAaveV4Spoke(payable(factory.createStrategy("AaveV4Spoke")));
        address[] memory rewards = new address[](1);
        rewards[0] = address(reward);
        strategy.initialize(address(spoke), 0, address(merkl), true, rewards, _addresses(address(want)));
        vault.initialize(IStrategyV7(address(strategy)), "Moo Test", "mooTEST", 21600);
    }

    function _addresses(address token) internal view returns (BaseAllToNativeFactoryStrat.Addresses memory) {
        return BaseAllToNativeFactoryStrat.Addresses(
            token, address(0), address(factory), address(vault), address(swapper), strategist
        );
    }

    function _deposit(address u, uint256 amount) internal {
        want.mint(u, amount);
        vm.startPrank(u);
        want.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    function _reward(uint256 amount) internal {
        reward.mint(address(merkl), amount);
        merkl.setRoot(address(strategy), address(reward), amount);
    }

    function _claim(uint256 amount) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(reward);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        strategy.claim(tokens, amounts, new bytes32[][](1));
    }

    function test_depositWithdrawAndNoRewardOnPrincipal() public {
        _deposit(user, 100e8);
        assertEq(strategy.storedBalance(), 100e8);
        strategy.harvest();
        assertEq(native.balanceOf(treasury), 0);
        vm.prank(user);
        vault.withdrawAll();
        assertEq(want.balanceOf(user), 100e8);
        assertEq(strategy.storedBalance(), 0);
        assertEq(spoke.shares(address(strategy)), 0);
    }

    function test_interestIsExcludedUntilHarvestAndThenLocked() public {
        _deposit(user, 100e8);
        spoke.setIndex(1.1e18);
        want.mint(address(spoke), 10e8);
        assertEq(strategy.balanceOf(), 100e8);
        strategy.harvest(address(0xFEE));
        assertApproxEqAbs(strategy.balanceOf(), 100e8, 2);
        assertApproxEqAbs(strategy.lockedProfit(), 9.55e8, 2);
        assertGt(native.balanceOf(treasury), 0);
        vm.warp(block.timestamp + 1 hours);
        assertApproxEqAbs(strategy.lockedProfit(), uint256(9.55e8) * 23 / 24, 2);
        vm.warp(block.timestamp + 23 hours);
        assertEq(strategy.lockedProfit(), 0);
        vm.prank(user);
        vault.withdrawAll();
        assertApproxEqAbs(want.balanceOf(user), 109.55e8, 3);
    }

    function test_merklFeesAndLockCheckpoint() public {
        _deposit(user, 100e8);
        _reward(10e6);
        _claim(10e6);
        assertEq(strategy.balanceOf(), 100e8);
        strategy.harvest(address(0xFEE));
        assertEq(strategy.lockedProfit(), 9.55e8);
        assertEq(native.balanceOf(treasury), 0.36e18);
        vm.warp(block.timestamp + 1800);
        uint256 locked = strategy.lockedProfit();
        uint256 balance = strategy.balanceOf();
        vm.prank(keeper);
        strategy.setLockDuration(600);
        assertEq(strategy.lockedProfit(), locked);
        assertEq(strategy.balanceOf(), balance);
        strategy.setHarvestOnDeposit(false);
        strategy.setHarvestOnDeposit(true);
        assertEq(strategy.lockDuration(), 600);
        assertEq(strategy.lockedProfit(), locked);
        vm.expectRevert("!duration");
        strategy.setLockDuration(0);
        vm.prank(user);
        vm.expectRevert(BaseAllToNativeFactoryStrat.NotManager.selector);
        strategy.setLockDuration(1);
        vm.warp(block.timestamp + 600);
        assertEq(strategy.lockedProfit(), 0);
    }

    function test_lockDurationBoundPreservesCheckpointAndRecovery() public {
        _deposit(user, 100e8);
        _reward(10e6);
        _claim(10e6);
        strategy.harvest(address(0xFEE));
        vm.warp(block.timestamp + 1800);
        uint256 locked = strategy.lockedProfit();
        uint256 lastHarvest = strategy.lastHarvest();

        vm.expectRevert("!duration");
        strategy.setLockDuration(7 days + 1);
        vm.expectRevert("!duration");
        strategy.setLockDuration(type(uint256).max);
        assertEq(strategy.lockDuration(), 1 days);
        assertEq(strategy.lastHarvest(), lastHarvest);
        assertEq(strategy.lockedProfit(), locked);

        strategy.setLockDuration(7 days);
        assertEq(strategy.lockedProfit(), locked);
        vm.warp(block.timestamp + 3 days);
        assertEq(strategy.lockedProfit(), locked * 4 / 7);
        uint256 remaining = strategy.lockedProfit();
        strategy.setLockDuration(1 hours);
        assertEq(strategy.lockedProfit(), remaining);
        vm.warp(block.timestamp + 1 hours);
        assertEq(strategy.lockedProfit(), 0);
        vm.prank(user);
        vault.withdrawAll();
        assertApproxEqAbs(want.balanceOf(user), 109.55e8, 3);
    }

    function test_hodHarvestsBeforeNewSharesAreMinted() public {
        _deposit(user, 100e8);
        _reward(10e6);
        _claim(10e6);
        _deposit(address(0x555), 100e8);
        assertEq(vault.balanceOf(user), vault.balanceOf(address(0x555)));
        assertEq(strategy.lockedProfit(), 9.55e8);
        assertTrue(strategy.harvestOnDeposit());
        assertEq(strategy.lockDuration(), 1 days);
    }

    function _attack(bool hod, bool direct) internal {
        strategy.setHarvestOnDeposit(hod);
        _deposit(user, 100e8);
        _reward(100e6);
        FlashLender lender = new FlashLender();
        want.mint(address(lender), 10000e8);
        FlashAttacker attacker =
            new FlashAttacker(IERC20(address(want)), vault, strategy, address(reward), 100e6, direct);
        want.mint(address(attacker), 2); // Allow a rounding unit without concealing any reward extraction.
        lender.lend(IERC20(address(want)), 10000e8, attacker);
        assertLe(want.balanceOf(address(attacker)), 2);
        assertEq(want.balanceOf(address(lender)), 10000e8);
        assertEq(strategy.lockedProfit(), 95.5e8);
        assertEq(strategy.balanceOf(), 100e8);
    }

    function test_flashloanClaimHarvestWithdrawHodOn() public {
        _attack(true, false);
    }

    function test_flashloanClaimHarvestWithdrawHodOff() public {
        _attack(false, false);
    }

    function test_flashloanDirectDistributorClaimHodOn() public {
        _attack(true, true);
    }

    function test_flashloanDirectDistributorClaimHodOff() public {
        _attack(false, true);
    }

    function test_claimForcesStrategyRecipientAndRejectsBadLengths() public {
        _reward(10e6);
        vm.prank(user);
        _claim(10e6);
        assertEq(reward.balanceOf(user), 0);
        assertEq(reward.balanceOf(address(strategy)), 10e6);
        vm.expectRevert("proof");
        _claim(10e6);
        vm.expectRevert("!length");
        strategy.claim(new address[](1), new uint256[](0), new bytes32[][](1));
    }

    function test_claimWantSwapsOnlyReceivedReward() public {
        want.mint(address(strategy), 100e8);
        want.mint(address(merkl), 10e8);
        merkl.setRoot(address(strategy), address(want), 10e8);
        address[] memory tokens = new address[](1);
        tokens[0] = address(want);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10e8;
        strategy.claim(tokens, amounts, new bytes32[][](1));
        assertEq(want.balanceOf(address(strategy)), 100e8);
        assertEq(native.balanceOf(address(strategy)), 10e18);
        strategy.harvest();
        assertEq(strategy.lockedProfit(), 9.55e8);
    }

    function test_panicUnpauseAndRetire() public {
        _deposit(user, 100e8);
        strategy.panic();
        assertEq(spoke.shares(address(strategy)), 0);
        assertEq(strategy.storedBalance(), 0);
        assertEq(want.balanceOf(address(strategy)), 100e8);
        vm.expectRevert(BaseAllToNativeFactoryStrat.StrategyPaused.selector);
        strategy.deposit();
        strategy.unpause();
        assertEq(strategy.storedBalance(), 100e8);
        vm.prank(address(vault));
        strategy.retireStrat();
        assertEq(want.balanceOf(address(vault)), 100e8);
        assertEq(spoke.shares(address(strategy)), 0);
    }

    // Synthetic loss stress test, not a model of normal Aave interest accrual.
    function test_syntheticLossDoesNotLeavePhantomPrincipalOrUnderflow() public {
        _deposit(user, 100e8);
        _reward(100e6);
        _claim(100e6);
        strategy.harvest();
        spoke.simulateLoss(0.1e18);
        assertEq(strategy.balanceOf(), 0);
        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        vault.withdrawAll();
        assertEq(strategy.balanceOf(), 0);
    }

    function testFuzz_roundingDoesNotOverstatePosition(uint256 amount, uint256 rate) public {
        amount = bound(amount, 100, 1e14);
        rate = bound(rate, 1e18, 3e18);
        spoke.setIndex(rate);
        _deposit(user, amount);
        assertLe(strategy.storedBalance(), spoke.getUserSuppliedAssets(0, address(strategy)));
        assertApproxEqAbs(strategy.storedBalance(), amount, 3);
        vm.prank(user);
        vault.withdrawAll();
        assertLe(want.balanceOf(user), amount);
        assertLe(strategy.balanceOfPool(), 3);
    }

    function test_zeroShareSupplyStaysIdle() public {
        spoke.setIndex(2e18);
        vm.expectRevert("!amount");
        spoke.supply(0, 0, address(this));
        vm.expectRevert("!shares");
        spoke.supply(0, 1, address(this));
        vm.expectRevert("!amount");
        spoke.withdraw(0, 0, address(this));
        want.mint(user, 1);
        vm.startPrank(user);
        want.approve(address(vault), 1);
        vault.deposit(1);
        vm.stopPrank();
        assertEq(want.balanceOf(address(strategy)), 1);
        assertEq(spoke.shares(address(strategy)), 0);
        vm.prank(user);
        vault.withdrawAll();
        assertEq(want.balanceOf(user), 1);
    }

    function test_initializationValidation() public {
        StrategyAaveV4Spoke fresh = StrategyAaveV4Spoke(payable(factory.createStrategy("AaveV4Spoke")));
        vm.expectRevert("!want");
        fresh.initialize(address(spoke), 0, address(merkl), true, new address[](0), _addresses(address(reward)));
        vm.expectRevert("!claimer");
        fresh.initialize(address(spoke), 0, user, true, new address[](0), _addresses(address(want)));
        MockSpoke nativeSpoke = new MockSpoke(address(native));
        vm.expectRevert("!nativeWant");
        fresh.initialize(address(nativeSpoke), 0, address(merkl), true, new address[](0), _addresses(address(native)));
        vm.expectRevert("Initializable: contract is already initialized");
        strategy.initialize(address(spoke), 0, address(merkl), true, new address[](0), _addresses(address(want)));
    }

    /// @dev No rewards, interest or donations: every actor's withdrawals must be funded by its own deposits.
    /// Exercise the real BeefyVaultV7 with three independently tracked actors and many interleaved actions.
    function testFuzz_multiUserPrincipalConservation(uint256 seed, uint256 rate, bool hod) public {
        spoke.setIndex(bound(rate, 1e18, 3e18));
        strategy.setHarvestOnDeposit(hod);
        // The production vault receives a permanent ~$1 strategist seed before user deposits.
        _deposit(strategist, 1e6);
        address[3] memory actors = [user, address(0x555), address(0x666)];
        uint256[3] memory contributed;
        for (uint256 i; i < 3; ++i) {
            contributed[i] = 100e8;
            _deposit(actors[i], contributed[i]);
        }
        for (uint256 step; step < 64; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 who = seed % 3;
            uint256 action = (seed >> 8) % 5;
            if (action == 0) {
                uint256 amount = 100e8 + (seed >> 16) % 100e8;
                contributed[who] += amount;
                _deposit(actors[who], amount);
            } else if (action == 1) {
                uint256 shares = vault.balanceOf(actors[who]);
                if (shares > 0) {
                    uint256 amount = 1 + (seed >> 16) % shares;
                    vm.prank(actors[who]);
                    vault.withdraw(amount);
                }
            } else if (action == 2) {
                vm.prank(actors[who]);
                strategy.harvest(address(0xFEE));
            } else if (action == 3) {
                vm.prank(actors[who]);
                vault.earn();
            } else {
                vm.warp(block.timestamp + (seed >> 16) % 3601);
            }
            uint256 backing = want.balanceOf(address(strategy)) + spoke.getUserSuppliedAssets(0, address(strategy));
            assertLe(strategy.balanceOf() + strategy.lockedProfit(), backing, "unbacked reported assets");
            for (uint256 i; i < 3; ++i) {
                assertLe(want.balanceOf(actors[i]), contributed[i], "withdrew another user's principal");
            }
        }
        for (uint256 i; i < 3; ++i) {
            if (vault.balanceOf(actors[i]) > 0) {
                vm.prank(actors[i]);
                vault.withdrawAll();
            }
            assertLe(want.balanceOf(actors[i]), contributed[i], "profited without yield");
            // At most a few atomic units per share conversion, not a percentage tolerance.
            assertApproxEqAbs(want.balanceOf(actors[i]), contributed[i], 600, "principal loss beyond rounding");
        }
    }

    function testFuzz_repeatedAttackerRoundTrips(uint256 amount, uint256 rate, bool hod) public {
        spoke.setIndex(bound(rate, 1e18, 3e18));
        strategy.setHarvestOnDeposit(hod);
        _deposit(strategist, 1e6);
        _deposit(user, 1000e8);
        address attacker = address(0xBAD);
        amount = bound(amount, 1000, 100000e8);
        want.mint(attacker, amount);
        vm.prank(attacker);
        want.approve(address(vault), type(uint256).max);
        for (uint256 i; i < 64; ++i) {
            uint256 available = want.balanceOf(attacker);
            vm.startPrank(attacker);
            vault.deposit(available);
            strategy.harvest(address(0xFEE));
            uint256 shares = vault.balanceOf(attacker);
            vault.withdraw(shares / 2);
            vault.withdrawAll();
            vm.stopPrank();
            assertLe(want.balanceOf(attacker), amount, "round-trip extracted principal");
        }
        vm.prank(user);
        vault.withdrawAll();
        assertApproxEqAbs(want.balanceOf(user), 1000e8, 600, "victim principal loss beyond rounding");
        assertGt(vault.balanceOf(strategist), 0, "permanent seed shares disappeared");
    }

    /// @dev The seed is left in place; donation plus a zero-share victim deposit must cost the attacker money.
    function testFuzz_seededDonationCannotProfit(uint256 attackerAmount, uint256 donation, uint256 victimAmount)
        public
    {
        _deposit(strategist, 1e6);
        address attacker = address(0xBAD);
        attackerAmount = bound(attackerAmount, 1e6, 100000e8);
        donation = bound(donation, 1, 100000e8);
        victimAmount = bound(victimAmount, 1, 100000e8);
        _deposit(attacker, attackerAmount);
        want.mint(attacker, donation);
        vm.prank(attacker);
        want.transfer(address(strategy), donation);
        _deposit(user, victimAmount);
        vm.prank(attacker);
        vault.withdrawAll();
        assertLe(want.balanceOf(attacker), attackerAmount + donation, "attacker took net victim principal");
        assertEq(vault.balanceOf(strategist), 1e6);
    }

    /// @dev The seed prevents the ordinary single-victim inflation attack, but V7 still accepts zero-share deposits.
    function test_seededVaultCanAccumulateZeroShareDeposits() public {
        _deposit(strategist, 1e6);
        address attacker = address(0xBAD);
        _deposit(attacker, 100e8);
        want.mint(attacker, 1);
        vm.prank(attacker);
        want.transfer(address(strategy), 1);
        _deposit(user, 1);
        _deposit(address(0x555), 1);
        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(0x555)), 0);
        vm.prank(attacker);
        vault.withdrawAll();
        assertGt(want.balanceOf(attacker), 100e8 + 1, "attacker did not capture deposited dust");
    }

    function test_publicHarvestDoesNotChargeIdlePrincipal() public {
        _deposit(user, 100e8);
        strategy.panic();
        // Paused principal remains withdrawable through the vault.
        uint256 halfShares = vault.balanceOf(user) / 2;
        vm.prank(user);
        vault.withdraw(halfShares);
        assertEq(want.balanceOf(user), 50e8);
        strategy.unpause();
        want.mint(address(strategy), 7e8);
        vm.prank(address(0xBAD));
        strategy.harvest(address(0xBAD));
        assertEq(native.balanceOf(address(0xBAD)), 0);
        assertEq(native.balanceOf(treasury), 0);
        assertEq(want.balanceOf(address(strategy)), 7e8);
        assertEq(strategy.balanceOf(), 57e8);
    }

    function test_panicWithInterestAndLockPreservesPrincipal() public {
        _deposit(user, 100e8);
        _reward(10e6);
        _claim(10e6);
        strategy.harvest(address(0xFEE));
        uint256 locked = strategy.lockedProfit();
        spoke.setIndex(1.1e18);
        want.mint(address(spoke), 20e8);
        uint256 backing = spoke.getUserSuppliedAssets(0, address(strategy));
        strategy.panic();
        assertEq(want.balanceOf(address(strategy)), backing);
        assertEq(strategy.lockedProfit(), locked);
        assertEq(strategy.balanceOf(), backing - locked);
        strategy.unpause();
        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        vault.withdrawAll();
        assertGe(want.balanceOf(user), 100e8, "principal lost on emergency round-trip");
        assertApproxEqAbs(want.balanceOf(user), backing, 3);
    }

    function test_unprivilegedCallsCannotRedirectPrincipal() public {
        _deposit(user, 100e8);
        address attacker = address(0xBAD);
        vm.startPrank(attacker);
        vm.expectRevert("!vault");
        strategy.withdraw(100e8);
        vm.expectRevert("!vault");
        strategy.retireStrat();
        vm.expectRevert(BaseAllToNativeFactoryStrat.NotManager.selector);
        strategy.panic();
        vm.expectRevert(BaseAllToNativeFactoryStrat.NotManager.selector);
        strategy.setClaimer(attacker);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setVault(attacker);
        vm.expectRevert("Ownable: caller is not the owner");
        strategy.setSwapper(attacker);
        strategy.deposit();
        strategy.harvest(attacker);
        vm.stopPrank();
        assertEq(want.balanceOf(attacker), 0);
        vm.prank(user);
        vault.withdrawAll();
        assertEq(want.balanceOf(user), 100e8);
    }

    function test_failedFinalSwapRollsBackInterestWithdrawalAndFees() public {
        _deposit(user, 100e8);
        spoke.setIndex(1.1e18);
        want.mint(address(spoke), 10e8);
        reward.mint(address(strategy), 10e6);
        vm.mockCallRevert(
            address(swapper),
            abi.encodeWithSelector(bytes4(keccak256("swap(address,address,uint256)")), address(native), address(want)),
            abi.encodeWithSignature("Error(string)", "slippage")
        );
        vm.expectRevert("slippage");
        strategy.harvest(address(0xFEE));
        assertEq(spoke.getUserSuppliedAssets(0, address(strategy)), 110e8);
        assertEq(strategy.storedBalance(), 100e8);
        assertEq(strategy.lockedProfit(), 0);
        assertEq(reward.balanceOf(address(strategy)), 10e6);
        assertEq(native.balanceOf(address(strategy)), 0);
        assertEq(native.balanceOf(treasury), 0);
        assertEq(native.balanceOf(strategist), 0);
        assertEq(native.balanceOf(address(0xFEE)), 0);
        // Withdrawals do not depend on the failing reward swap route.
        vm.prank(user);
        vault.withdrawAll();
        assertEq(want.balanceOf(user), 100e8);
    }

    function testFuzz_factoryPauseStillAllowsWithdrawals(bool global) public {
        _deposit(user, 100e8);
        if (global) factory.pauseAllStrats();
        else factory.pauseStrategy("AaveV4Spoke");
        vm.expectRevert(BaseAllToNativeFactoryStrat.StrategyPaused.selector);
        strategy.harvest();
        vm.expectRevert(BaseAllToNativeFactoryStrat.StrategyPaused.selector);
        strategy.deposit();
        vm.prank(user);
        vault.withdrawAll();
        assertEq(want.balanceOf(user), 100e8);
    }

    function test_repeatedHarvestPreservesRemainingLock() public {
        _deposit(user, 100e8);
        reward.mint(address(strategy), 10e6);
        strategy.harvest(address(0xFEE));
        uint256 last = strategy.lastHarvest();
        vm.warp(block.timestamp + 900);
        uint256 remaining = strategy.lockedProfit();
        uint256 before = strategy.balanceOf();
        strategy.harvest(address(0xFEE));
        assertEq(strategy.lastHarvest(), last, "empty harvest restarted the lock");
        assertEq(strategy.lockedProfit(), remaining);
        reward.mint(address(strategy), 10e6);
        strategy.harvest(address(0xFEE));
        assertEq(strategy.lockedProfit(), remaining + 9.55e8);
        assertEq(strategy.balanceOf(), before, "new locked rewards changed redeemable balance");
        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        vault.withdrawAll();
        assertEq(want.balanceOf(user), 119.1e8);
    }

    function test_interestAndNativeThresholdsDoNotDoubleCountOrChargePrincipal() public {
        _deposit(user, 100e8);
        spoke.setIndex(1.1e18);
        want.mint(address(spoke), 10e8);
        strategy.setRewardMinAmount(address(want), 10e8);
        strategy.harvest(address(0xFEE));
        assertEq(native.balanceOf(address(strategy)), 0);
        assertEq(spoke.getUserSuppliedAssets(0, address(strategy)), 110e8);
        assertEq(strategy.balanceOf(), 100e8);
        strategy.setRewardMinAmount(address(want), 0);
        strategy.setRewardMinAmount(address(native), 20e18);
        strategy.harvest(address(0xFEE));
        assertEq(native.balanceOf(address(strategy)), 10e18);
        assertEq(native.balanceOf(treasury), 0);
        assertEq(strategy.lockedProfit(), 0);
        assertApproxEqAbs(strategy.balanceOf(), 100e8, 2);
        strategy.harvest(address(0xFEE));
        assertEq(native.balanceOf(address(strategy)), 10e18, "interest counted twice");
        strategy.setRewardMinAmount(address(native), 0);
        strategy.harvest(address(0xFEE));
        assertEq(native.balanceOf(treasury), 0.36e18);
        assertEq(strategy.lockedProfit(), 9.55e8);
        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        vault.withdrawAll();
        assertApproxEqAbs(want.balanceOf(user), 109.55e8, 3);
    }

    function testFuzz_multiUserInterestAndLockedRewards(uint256 seed, bool hod) public {
        strategy.setHarvestOnDeposit(hod);
        _deposit(strategist, 1e6);
        address[2] memory actors = [user, address(0x555)];
        uint256[2] memory contributed = [uint256(100e8), uint256(100e8)];
        _deposit(actors[0], contributed[0]);
        _deposit(actors[1], contributed[1]);
        for (uint256 step; step < 32; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 who = seed % 2;
            uint256 action = (seed >> 8) % 5;
            if (action == 0) {
                uint256 amount = 1e8 + (seed >> 16) % 100e8;
                contributed[who] += amount;
                _deposit(actors[who], amount);
            } else if (action == 1) {
                uint256 shares = vault.balanceOf(actors[who]) / 2;
                vm.prank(actors[who]);
                vault.withdraw(shares);
            } else if (action == 2) {
                uint256 before = spoke.getUserSuppliedAssets(0, address(strategy));
                spoke.setIndex(spoke.index() + 1e15 + (seed >> 16) % 1e16);
                uint256 afterBal = spoke.getUserSuppliedAssets(0, address(strategy));
                want.mint(address(spoke), afterBal - before);
            } else if (action == 3) {
                reward.mint(address(strategy), 1e6);
                strategy.harvest(address(0xFEE));
            } else {
                vm.warp(block.timestamp + (seed >> 16) % 3601);
            }
            uint256 backing = want.balanceOf(address(strategy)) + spoke.getUserSuppliedAssets(0, address(strategy));
            assertLe(strategy.balanceOf() + strategy.lockedProfit(), backing, "reported assets exceed backing");
        }
        strategy.harvest(address(0xFEE));
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 2; ++i) {
            vm.prank(actors[i]);
            vault.withdrawAll();
            assertGe(want.balanceOf(actors[i]) + 300, contributed[i], "user lost principal beyond rounding");
        }
    }

    /// @dev Vulnerability reproduction, NOT a safety assertion. The unseeded V7 vault permits zero-share deposits.
    function test_reproduceFirstDepositorDonationTheft() public {
        address attacker = address(0xBAD);
        _deposit(attacker, 1);
        want.mint(attacker, 100e8);
        vm.prank(attacker);
        want.transfer(address(strategy), 100e8);
        _deposit(user, 100e8);
        assertEq(vault.balanceOf(user), 0, "victim deposit rounded down to zero shares");
        vm.prank(attacker);
        vault.withdrawAll();
        assertEq(want.balanceOf(attacker), 200e8 + 1);
        assertEq(want.balanceOf(user), 0);
    }
}
