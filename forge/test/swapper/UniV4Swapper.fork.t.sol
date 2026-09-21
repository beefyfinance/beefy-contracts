// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin-5/contracts/token/ERC20/IERC20.sol";
import {UniV4Swapper} from "../../../contracts/BIFI/utils/UniV4Swapper.sol";
import {IUniversalRouter} from "../../../contracts/BIFI/interfaces/common/IUniversalRouter.sol";
import {IWrappedNative} from "../../../contracts/BIFI/interfaces/common/IWrappedNative.sol";

interface IExtsload {
    function extsload(bytes32 slot) external view returns (bytes32);
}

/// @title UniV4Swapper fork tests
/// @notice Swaps native -> TOKEN and TOKEN -> native through a single native/TOKEN v4 pool, plus
///         TOKEN -> TOKEN2 through a TOKEN/TOKEN2 pool as an ERC20-only control.
///         Every setting comes from env (defaulting to Base)
///
///         UNIV4_RPC=monad UNIV4_FORK_BLOCK=0 UNIV4_ROUTER=0x... UNIV4_NATIVE=0x... UNIV4_TOKEN=0x... \
///         UNIV4_FEE=3000 UNIV4_TICK_SPACING=60 UNIV4_TOKEN2=0x... UNIV4_TOKEN2_FEE=100 UNIV4_TOKEN2_TICK_SPACING=1 \
///         forge test --mp forge/test/swapper/UniV4Swapper.fork.t.sol
///
///         UNIV4_FORK_BLOCK=0 forks at the latest block.
contract UniV4SwapperForkTest is Test {
    struct Pool {
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6)); // PoolManager.pools

    uint256 internal forkBlock;
    address internal router;
    address internal permit2;
    address internal native;
    address internal token;
    address internal token2;
    Pool internal nativePool; // native/TOKEN
    Pool internal tokenPool; // TOKEN/TOKEN2
    uint256 internal amount; // native amount; the TOKEN amount is its spot-price equivalent
    bool internal nativeIsMirrored;

    address internal user = makeAddr("user");
    UniV4Swapper internal swapper;

    function setUp() public {
        string memory rpc = vm.envOr("UNIV4_RPC", vm.envOr("BASE_RPC", string("https://mainnet.base.org")));
        forkBlock = vm.envOr("UNIV4_FORK_BLOCK", uint256(51_470_000));
        router = vm.envOr("UNIV4_ROUTER", 0xd6145b2D3F379919E8CdEda7B97e37c4b2Ca9c40); // UniversalRouter 2.1.2
        permit2 = vm.envOr("UNIV4_PERMIT2", 0x000000000022D473030F116dDEE9F6B43aC78BA3);
        native = vm.envOr("UNIV4_NATIVE", 0x4200000000000000000000000000000000000006);
        token = vm.envOr("UNIV4_TOKEN", 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        nativePool = Pool(
            uint24(vm.envOr("UNIV4_FEE", uint256(500))),
            int24(vm.envOr("UNIV4_TICK_SPACING", int256(10))),
            vm.envOr("UNIV4_HOOKS", address(0))
        );
        token2 = vm.envOr("UNIV4_TOKEN2", 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);
        tokenPool = Pool(
            uint24(vm.envOr("UNIV4_TOKEN2_FEE", uint256(500))),
            int24(vm.envOr("UNIV4_TOKEN2_TICK_SPACING", int256(10))),
            vm.envOr("UNIV4_TOKEN2_HOOKS", address(0))
        );
        amount = vm.envOr("UNIV4_AMOUNT", uint256(1 ether));
        nativeIsMirrored = vm.envOr("UNIV4_NATIVE_IS_MIRRORED", false);

        if (forkBlock == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, forkBlock);
        swapper = new UniV4Swapper(permit2, router, native, nativeIsMirrored);
    }

    function test_swap_nativeIn() public {
        uint256 expected = _quote(address(0), token, nativePool, amount);
        vm.deal(user, amount);

        vm.startPrank(user);
        IWrappedNative(native).deposit{value: amount}();
        IERC20(native).approve(address(swapper), amount);
        swapper.swap(address(0), token, amount, 0, _path(token, nativePool));
        vm.stopPrank();

        assertApproxEqRel(IERC20(token).balanceOf(user), expected, 0.01e18, "token out vs pool price");
        assertEq(IERC20(native).balanceOf(user), 0);
        assertEq(router.balance, 0, "native left in router");
        _assertSwapperEmpty();
    }

    function test_swap_nativeOut() public {
        uint256 tokenAmount = _quote(address(0), token, nativePool, amount);
        uint256 expected = _quote(token, address(0), nativePool, tokenAmount);
        deal(token, user, tokenAmount);

        vm.startPrank(user);
        IERC20(token).approve(address(swapper), tokenAmount);
        swapper.swap(token, address(0), tokenAmount, 0, _path(address(0), nativePool));
        vm.stopPrank();

        assertApproxEqRel(IERC20(native).balanceOf(user), expected, 0.01e18, "native out vs pool price");
        assertEq(IERC20(token).balanceOf(user), 0);
        _assertSwapperEmpty();
    }

    function test_swap_tokenToToken() public {
        uint256 tokenAmount = _quote(address(0), token, nativePool, amount);
        uint256 expected = _quote(token, token2, tokenPool, tokenAmount);
        deal(token, user, tokenAmount);

        vm.startPrank(user);
        IERC20(token).approve(address(swapper), tokenAmount);
        swapper.swap(token, token2, tokenAmount, 0, _path(token2, tokenPool));
        vm.stopPrank();

        assertApproxEqRel(IERC20(token2).balanceOf(user), expected, 0.01e18, "token2 out vs pool price");
        assertEq(IERC20(token).balanceOf(user), 0);
        _assertSwapperEmpty();
    }

    function _path(address intermediate, Pool memory pool) internal pure returns (UniV4Swapper.PathKey[] memory path) {
        path = new UniV4Swapper.PathKey[](1);
        path[0] = UniV4Swapper.PathKey(intermediate, pool.fee, pool.tickSpacing, pool.hooks, "");
    }

    /// @dev Spot-price quote less the LP fee (impact ignored; callers allow 1%). address(0) is native.
    function _quote(address tokenIn, address tokenOut, Pool memory pool, uint256 amountIn) internal view returns (uint256) {
        (address currency0, address currency1) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        bytes32 poolId = keccak256(abi.encode(currency0, currency1, pool.fee, pool.tickSpacing, pool.hooks));
        uint256 slot0 = uint256(IExtsload(IUniversalRouter(router).poolManager()).extsload(keccak256(abi.encode(poolId, POOLS_SLOT))));
        uint256 p = uint160(slot0);
        require(p != 0, "pool not initialized");
        uint256 lpFee = uint24(slot0 >> 208);

        uint256 out = tokenIn == currency0 ? amountIn * p / 2 ** 96 * p / 2 ** 96 : amountIn * 2 ** 96 / p * 2 ** 96 / p;
        return out * (1e6 - lpFee) / 1e6;
    }

    function _assertSwapperEmpty() internal view {
        assertEq(address(swapper).balance, 0, "swapper native");
        assertEq(IERC20(native).balanceOf(address(swapper)), 0, "swapper wrapped native");
        assertEq(IERC20(token).balanceOf(address(swapper)), 0, "swapper token");
        assertEq(IERC20(token2).balanceOf(address(swapper)), 0, "swapper token2");
    }
}
