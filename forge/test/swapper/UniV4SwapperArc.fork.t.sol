// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin-5/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UniV4Swapper} from "../../../contracts/BIFI/utils/UniV4Swapper.sol";
import {IUniversalRouter} from "../../../contracts/BIFI/interfaces/common/IUniversalRouter.sol";

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct ModifyLiquidityParams {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidityDelta;
    bytes32 salt;
}

interface IPoolManagerLike {
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);
    function unlock(bytes calldata data) external returns (bytes memory);
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (int256 callerDelta, int256 feesAccrued);
    function sync(address currency) external;
    function settle() external payable returns (uint256);
}

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Stands in for Arc's native-transfer precompile, which foundry's EVM cannot execute.
///      It moves real balances so the mirrored accounting under test stays honest.
contract NativeTransferPrecompile {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function transfer(address from, address to, uint256 amount) external returns (bool) {
        require(from.balance >= amount, "precompile: insufficient balance");
        vm.deal(from, from.balance - amount);
        vm.deal(to, to.balance + amount);
        return true;
    }
}

/// @title UniV4Swapper fork tests on Arc, whose native token is mirrored (nativeIsMirrored)
/// @notice On Arc USDC is the gas token: native accounting uses 18 decimals while
///         its ERC20 interface at 0x3600..0000 exposes 6, and the two balances mirror each other
///         (balanceOf == address.balance / 1e12). There is no WETH9-style wrapper, so the swapper
///         must skip deposit/withdraw and scale amounts by 1e12 for the router. Arc has v4 pools
///         keyed on both currencies; this covers the ones keyed on native (address(0)).
///
///         Uses the chain's real UniversalRouter and PoolManager, but creates its own native/MOCK
///         pool at a 1:1 price so the expected amounts don't depend on live liquidity. Arc's USDC
///         precompiles are stubbed (see NativeTransferPrecompile).
contract UniV4SwapperArcForkTest is Test {
    uint24 internal constant FEE = 500;
    int24 internal constant TICK_SPACING = 10;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // 1 native wei : 1 MOCK wei
    uint128 internal constant LIQUIDITY = 1_000_000e18;

    /// @dev Arc's USDC delegates to these chain precompiles, which foundry's EVM cannot execute.
    address internal constant BLOCKLIST = 0x1800000000000000000000000000000000000001;
    address internal constant NATIVE_TRANSFER = 0x1800000000000000000000000000000000000000;

    address internal router;
    address internal permit2;
    address internal native; // ERC20 interface of the gas token
    address internal poolManager;
    uint256 internal amount; // in native ERC20 units, as callers pass them
    uint256 internal scale; // native wei per ERC20 unit

    address internal user = makeAddr("user");
    UniV4Swapper internal swapper;
    MockToken internal token;
    PoolKey internal key;

    function setUp() public {
        vm.createSelectFork(vm.envOr("UNIV4_RPC", string("https://rpc.mainnet.arc.io")));
        router = vm.envOr("UNIV4_ROUTER", 0x8702463e73f74d0b6765aBceb314Ef07aCb92650); // UniversalRouter 2.1.2
        permit2 = vm.envOr("UNIV4_PERMIT2", 0x000000000022D473030F116dDEE9F6B43aC78BA3);
        native = vm.envOr("UNIV4_NATIVE", 0x3600000000000000000000000000000000000000);
        amount = vm.envOr("UNIV4_AMOUNT", uint256(10e6));
        poolManager = IUniversalRouter(router).poolManager();

        vm.mockCall(BLOCKLIST, abi.encodeWithSignature("isBlocklisted(address)"), abi.encode(false));
        vm.etch(NATIVE_TRANSFER, address(new NativeTransferPrecompile()).code);
        vm.allowCheatcodes(NATIVE_TRANSFER);

        scale = 10 ** (18 - IERC20Metadata(native).decimals());
        swapper = new UniV4Swapper(permit2, router, native, true);
        token = new MockToken();
        _initPool();
    }

    /// @dev The ERC20 is a view of the native balance, not a wrapper holding deposits.
    function test_nativeIsMirrored() public {
        assertEq(swapper.nativeScale(), scale, "scale");
        vm.deal(user, amount * scale);
        assertEq(IERC20(native).balanceOf(user), amount, "ERC20 balance mirrors native");
    }

    /// @dev amount is in ERC20 units and has to be scaled up to native wei as the router's msg.value.
    function test_swap_nativeIn() public {
        vm.deal(user, amount * scale);

        vm.startPrank(user);
        IERC20(native).approve(address(swapper), amount);
        swapper.swap(address(0), address(token), amount, 0, _path(address(token)));
        vm.stopPrank();

        // 1:1 pool, so amount ERC20 units in -> ~amount * scale MOCK wei out
        assertApproxEqRel(token.balanceOf(user), _lessFee(amount * scale), 0.001e18, "MOCK out");
        assertEq(IERC20(native).balanceOf(user), 0, "user native spent");
        assertEq(user.balance, 0, "spent as native, not from a wrapper");
        _assertSwapperEmpty();
    }

    /// @dev Output arrives as native from the PoolManager and is paid out through the ERC20 view.
    function test_swap_nativeOut() public {
        uint256 tokenAmount = amount * scale;
        token.mint(user, tokenAmount);

        vm.startPrank(user);
        token.approve(address(swapper), tokenAmount);
        swapper.swap(address(token), address(0), tokenAmount, 0, _path(address(0)));
        vm.stopPrank();

        assertApproxEqRel(IERC20(native).balanceOf(user), _lessFee(tokenAmount) / scale, 0.001e18, "native out");
        assertEq(user.balance / scale, IERC20(native).balanceOf(user), "paid as native, not wrapped");
        assertEq(token.balanceOf(user), 0);
        _assertSwapperEmpty();
    }

    /// @dev minAmount is in ERC20 units too, so it has to be scaled up for TAKE_ALL.
    function test_swap_nativeOut_respectsMinAmount() public {
        uint256 tokenAmount = amount * scale;
        token.mint(user, tokenAmount);
        uint256 tooMuch = tokenAmount / scale; // the fee alone puts this out of reach

        vm.startPrank(user);
        token.approve(address(swapper), tokenAmount);
        vm.expectRevert(); // V4TooLittleReceived
        swapper.swap(address(token), address(0), tokenAmount, tooMuch, _path(address(0)));
        vm.stopPrank();
    }

    function _lessFee(uint256 amountIn) internal pure returns (uint256) {
        return amountIn * (1e6 - FEE) / 1e6;
    }

    function _path(address intermediate) internal pure returns (UniV4Swapper.PathKey[] memory path) {
        path = new UniV4Swapper.PathKey[](1);
        path[0] = UniV4Swapper.PathKey(intermediate, FEE, TICK_SPACING, address(0), "");
    }

    function _assertSwapperEmpty() internal view {
        // The payout is `IERC20(native).transfer(balanceOf(this))`, which can only move whole ERC20
        // units, so native-out leaves up to one unit (< 1e12 wei) of rounding dust in the swapper.
        assertLt(address(swapper).balance, scale, "swapper native above rounding dust");
        assertEq(IERC20(native).balanceOf(address(swapper)), 0, "swapper native erc20");
        assertEq(token.balanceOf(address(swapper)), 0, "swapper MOCK");
        assertEq(router.balance, 0, "native left in router");
    }

    function _initPool() internal {
        key = PoolKey(address(0), address(token), FEE, TICK_SPACING, address(0));
        IPoolManagerLike(poolManager).initialize(key, SQRT_PRICE_1_1);

        vm.deal(address(this), uint256(LIQUIDITY) * 2);
        token.mint(address(this), uint256(LIQUIDITY) * 2);
        IPoolManagerLike(poolManager).unlock("");
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        require(msg.sender == poolManager);
        (int256 delta,) = IPoolManagerLike(poolManager).modifyLiquidity(
            key, ModifyLiquidityParams(-887270, 887270, int256(uint256(LIQUIDITY)), bytes32(0)), ""
        );
        IPoolManagerLike(poolManager).settle{value: uint256(uint128(-int128(delta >> 128)))}();
        IPoolManagerLike(poolManager).sync(address(token));
        token.transfer(poolManager, uint256(uint128(-int128(delta))));
        IPoolManagerLike(poolManager).settle();
        return "";
    }

    receive() external payable {}
}
