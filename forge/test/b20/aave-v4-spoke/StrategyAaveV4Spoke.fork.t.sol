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

interface IMag7Status {
    function getUserReserveStatus(uint256 reserveId, address user)
        external
        view
        returns (bool collateral, bool borrowing);
}

/// @dev Real Base tokens, MAG7 and Hub; synthetic Merkl entitlement and funded deterministic swaps.
/// Requires Foundry >= 1.8.4 with hardfork base:Cobalt (set in the b20 profile) to execute B20 native precompiles.
/// Run: FOUNDRY_PROFILE=b20 forge test --match-contract StrategyAaveV4SpokeForkTest -vv
contract StrategyAaveV4SpokeForkTest is Test {
    using stdStorage for StdStorage;

    address constant MAG7 = 0x17905Db0e4A3514467539956c084180616AE7B8D;
    address constant HUB = 0xa4d5947Eb727A052bae69C593FfC84247EC9864E;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USER = address(0x111);
    address constant FEE_RECIPIENT = address(0xFEE);
    StrategyFactory factory;
    StrategyAaveV4Spoke strategy;
    BeefyVaultV7 vault;
    MockMerkl merkl;
    MockSwapper swapper;
    IERC20 want;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC", string("https://mainnet.base.org"));
        uint256 blockNumber = vm.envOr("AAVE_V4_FORK_BLOCK", uint256(52_602_172));
        vm.createSelectFork(rpc, blockNumber);
        BeefyFeeConfigurator fees = new BeefyFeeConfigurator();
        fees.initialize(address(this), 0.1e18);
        fees.setFeeCategory(0, 0.045e18, 0.1e18, 0.1e18, "test", true, false);
        factory = new StrategyFactory(WETH, address(this), address(0x333), address(fees));
        factory.addStrategy("AaveV4Spoke", address(new StrategyAaveV4Spoke()));
    }

    function _prepare(uint256 id, address expectedAsset) internal {
        IAaveV4Spoke.Reserve memory reserve = IAaveV4Spoke(MAG7).getReserve(id);
        assertEq(reserve.underlying, expectedAsset);
        assertEq(address(reserve.hub), HUB);
        want = IERC20(expectedAsset);
        merkl = new MockMerkl();
        swapper = new MockSwapper();
        swapper.setToken(expectedAsset, 1e8);
        swapper.setToken(USDC, 1e6);
        swapper.setToken(WETH, 1e18);
        _fund(expectedAsset, address(swapper), 10000e8);
        _fund(WETH, address(swapper), 10000e18);
        vault = new BeefyVaultV7();
        strategy = StrategyAaveV4Spoke(payable(factory.createStrategy("AaveV4Spoke")));
        address[] memory rewards = new address[](1);
        rewards[0] = USDC;
        strategy.initialize(
            MAG7,
            id,
            address(merkl),
            true,
            rewards,
            BaseAllToNativeFactoryStrat.Addresses(
                expectedAsset, address(0), address(factory), address(vault), address(swapper), address(0x444)
            )
        );
        vault.initialize(IStrategyV7(address(strategy)), "Moo MAG7 Test", "mooMAG7", 21600);
        assertEq(strategy.assetId(), reserve.assetId);
        assertEq(strategy.lockDuration(), 1 days);
    }

    /// @dev Native precompile storage reads are not recorded by stdStorage in Base Foundry v1.1.1.
    /// Fund B20 balances using the documented base.b20 ERC-7201 layout (balances offset 4).
    /// No token code, permission settings, or Aave accounting is replaced.
    /// https://github.com/base/base-std/blob/main/test/lib/mocks/MockB20Storage.sol
    function _fund(address token, address account, uint256 amount) internal {
        if (uint8(uint160(token) >> 152) == 0xb2) {
            bytes32 root = keccak256(abi.encode(uint256(keccak256("base.b20")) - 1)) & ~bytes32(uint256(0xff));
            bytes32 slot = keccak256(abi.encode(account, uint256(root) + 4));
            assertEq(uint256(vm.load(token, slot)), IERC20(token).balanceOf(account), "B20 layout mismatch");
            vm.store(token, slot, bytes32(amount));
            assertEq(IERC20(token).balanceOf(account), amount, "B20 funding failed");
        } else {
            deal(token, account, amount);
        }
    }

    function _deposit(uint256 amount) internal {
        _fund(address(want), USER, amount);
        vm.startPrank(USER);
        want.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    function _claim(uint256 amount) internal {
        _fund(USDC, address(merkl), amount);
        merkl.setRoot(address(strategy), USDC, amount);
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        strategy.claim(tokens, amounts, new bytes32[][](1));
    }

    function _exercise(uint256 id, address token) internal {
        _prepare(id, token);
        // This is at or below a ~$1 stock token seed across the MAG7 assets; leave its shares outstanding.
        address seedHolder = address(0x444);
        _fund(token, seedHolder, 1e5);
        vm.startPrank(seedHolder);
        want.approve(address(vault), 1e5);
        vault.deposit(1e5);
        vm.stopPrank();
        assertGt(vault.balanceOf(seedHolder), 0);
        _deposit(10e8);
        assertApproxEqAbs(strategy.balanceOfPool(), 10e8 + 1e5, 2);
        (bool collateral, bool borrowing) = IMag7Status(MAG7).getUserReserveStatus(id, address(strategy));
        assertFalse(collateral);
        assertFalse(borrowing);
        uint256 halfShares = vault.balanceOf(USER) / 2;
        vm.prank(USER);
        vault.withdraw(halfShares);
        assertApproxEqAbs(want.balanceOf(USER), 5e8, 2);
        vm.prank(USER);
        vault.withdrawAll();
        assertApproxEqAbs(want.balanceOf(USER), 10e8, 3);
        assertApproxEqAbs(IAaveV4Spoke(MAG7).getUserSuppliedAssets(id, address(strategy)), 1e5, 2);

        _deposit(100e8);
        _claim(10e6);
        uint256 before = strategy.balanceOf();
        strategy.harvest(FEE_RECIPIENT);
        assertGt(strategy.lockedProfit(), 0);
        assertApproxEqAbs(strategy.balanceOf(), before, 3);
        vm.warp(block.timestamp + 1 days);
        vm.prank(USER);
        vault.withdrawAll();
        assertGt(want.balanceOf(USER), 109e8);

        // An actual callback and principal repayment in one transaction, with direct distributor claim.
        _deposit(100e8);
        _fund(USDC, address(merkl), 100e6);
        merkl.setRoot(address(strategy), USDC, 100e6);
        FlashLender lender = new FlashLender();
        _fund(token, address(lender), 1000e8);
        FlashAttacker attacker = new FlashAttacker(want, vault, strategy, USDC, 100e6, true);
        _fund(token, address(attacker), 3);
        lender.lend(want, 1000e8, attacker);
        assertLe(want.balanceOf(address(attacker)), 3);
        assertEq(want.balanceOf(address(lender)), 1000e8);
        assertGt(strategy.lockedProfit(), 95e8);

        vm.warp(block.timestamp + 1 days);
        strategy.panic();
        assertEq(IAaveV4Spoke(MAG7).getUserSuppliedShares(id, address(strategy)), 0);
        assertEq(strategy.storedBalance(), 0);
        strategy.unpause();
        assertGt(strategy.storedBalance(), 195e8);
        vm.prank(address(vault));
        strategy.retireStrat();
        assertEq(IAaveV4Spoke(MAG7).getUserSuppliedShares(id, address(strategy)), 0);
        assertGt(want.balanceOf(address(vault)), 195e8);
    }

    function test_supplyCapRevertsDepositAndRecovers() public {
        _prepare(0, 0xb200000000000000000000C2e324d24d7eEcd1fb);
        _fund(address(want), USER, 100e8);
        vm.prank(USER);
        want.approve(address(vault), 100e8);
        uint256 snapshot = vm.snapshotState();
        // Change only the Hub's add cap on this fork; execute the real supply validation.
        stdstore.target(HUB)
            .sig("getSpokeConfig(uint256,address)")
            .with_key(strategy.assetId())
            .with_key(MAG7)
            .depth(0)
            .enable_packed_slots()
            .checked_write(uint256(0));
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSignature("AddCapExceeded(uint256)", 0));
        vault.deposit(100e8);
        assertEq(want.balanceOf(USER), 100e8);
        assertEq(vault.balanceOf(USER), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(strategy.storedBalance(), 0);

        assertTrue(vm.revertToState(snapshot));
        vm.prank(USER);
        vault.deposit(100e8);
        assertGt(vault.balanceOf(USER), 0);
        assertApproxEqAbs(strategy.balanceOfPool(), 100e8, 2);
    }

    function test_insufficientLiquidityPreservesSharesAndRecovers() public {
        _prepare(0, 0xb200000000000000000000C2e324d24d7eEcd1fb);
        _deposit(100e8);
        uint256 shares = vault.balanceOf(USER);
        uint256 principal = strategy.storedBalance();
        uint256 snapshot = vm.snapshotState();
        // Simulate exhausted available liquidity; keep real Hub/Spoke code and user positions.
        stdstore.target(HUB)
            .sig("getAssetLiquidity(uint256)")
            .with_key(strategy.assetId())
            .enable_packed_slots()
            .checked_write(uint256(0));
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity(uint256)", 0));
        vault.withdrawAll();
        assertEq(vault.balanceOf(USER), shares);
        assertEq(strategy.storedBalance(), principal);
        assertEq(want.balanceOf(USER), 0);

        assertTrue(vm.revertToState(snapshot));
        vm.prank(USER);
        vault.withdrawAll();
        assertEq(vault.balanceOf(USER), 0);
        assertApproxEqAbs(want.balanceOf(USER), 100e8, 3);
    }

    function test_seededDonationDoesNotStealPrincipalOnRealAave() public {
        _prepare(0, 0xb200000000000000000000C2e324d24d7eEcd1fb);
        address seedHolder = address(0x444);
        address attacker = address(0xBAD);
        _fund(address(want), seedHolder, 1e5);
        vm.startPrank(seedHolder);
        want.approve(address(vault), 1e5);
        vault.deposit(1e5);
        vm.stopPrank();
        _fund(address(want), attacker, 101e8);
        vm.startPrank(attacker);
        want.approve(address(vault), 1e8);
        vault.deposit(1e8);
        want.transfer(address(strategy), 100e8);
        vm.stopPrank();
        _deposit(100e8);
        vm.prank(attacker);
        vault.withdrawAll();
        assertLe(want.balanceOf(attacker), 101e8, "attacker extracted victim principal");
        assertGt(vault.balanceOf(seedHolder), 0);
    }

    function test_seededVaultCanCaptureAtomicDepositsOnRealAave() public {
        _prepare(0, 0xb200000000000000000000C2e324d24d7eEcd1fb);
        address seedHolder = address(0x444);
        address attacker = address(0xBAD);
        _fund(address(want), seedHolder, 1e5);
        vm.startPrank(seedHolder);
        want.approve(address(vault), 1e5);
        vault.deposit(1e5);
        vm.stopPrank();
        _fund(address(want), attacker, 100e8 + 1);
        vm.startPrank(attacker);
        want.approve(address(vault), 100e8);
        vault.deposit(100e8);
        want.transfer(address(strategy), 1);
        vm.stopPrank();
        _deposit(1);
        address secondUser = address(0x555);
        _fund(address(want), secondUser, 1);
        vm.startPrank(secondUser);
        want.approve(address(vault), 1);
        vault.deposit(1);
        vm.stopPrank();
        assertEq(vault.balanceOf(USER), 0);
        assertEq(vault.balanceOf(secondUser), 0);
        vm.prank(attacker);
        vault.withdrawAll();
        assertGt(want.balanceOf(attacker), 100e8 + 1);
    }

    function test_AAPLc() public {
        _exercise(0, 0xb200000000000000000000C2e324d24d7eEcd1fb);
    }

    function test_AMZNc() public {
        _exercise(1, 0xb200000000000000000000d9192b6B456483C2E8);
    }

    function test_GOOGLc() public {
        _exercise(2, 0xb2000000000000000000002D0BA3164cc74f58B7);
    }

    function test_METAc() public {
        _exercise(3, 0xb2000000000000000000008bC8786B856E61707C);
    }

    function test_MSFTc() public {
        _exercise(4, 0xB200000000000000000000Ab99cFa739E253872B);
    }

    function test_NVDAc() public {
        _exercise(5, 0xb20000000000000000000078ee7ce2fE4908108C);
    }

    function test_TSLAc() public {
        _exercise(6, 0xb2000000000000000000001e800a7f5189430cD0);
    }
}
