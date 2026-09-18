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
/// @notice Swaps native -> TOKEN and TOKEN -> native through a single native/TOKEN v4 pool.
///         Every setting comes from env (defaulting to Base)
///
///         UNIV4_RPC=monad UNIV4_FORK_BLOCK=0 UNIV4_ROUTER=0x... UNIV4_NATIVE=0x... UNIV4_TOKEN=0x... \
///         UNIV4_FEE=3000 UNIV4_TICK_SPACING=60 forge test --mp forge/test/swapper/UniV4Swapper.fork.t.sol
///
///         UNIV4_FORK_BLOCK=0 forks at the latest block.
contract UniV4SwapperForkTest is Test {
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6)); // PoolManager.pools

    uint256 internal forkBlock;
    address internal router;
    address internal permit2;
    address internal native;
    address internal token;
    uint24 internal fee;
    int24 internal tickSpacing;
    address internal hooks;
    uint256 internal amount; // native amount; the TOKEN amount is its spot-price equivalent

    address internal user = makeAddr("user");
    UniV4Swapper internal swapper;

    function setUp() public {
        string memory rpc = vm.envOr("UNIV4_RPC", vm.envOr("BASE_RPC", string("https://mainnet.base.org")));
        forkBlock = vm.envOr("UNIV4_FORK_BLOCK", uint256(51_470_000));
        router = vm.envOr("UNIV4_ROUTER", 0x6fF5693b99212Da76ad316178A184AB56D299b43);
        permit2 = vm.envOr("UNIV4_PERMIT2", 0x000000000022D473030F116dDEE9F6B43aC78BA3);
        native = vm.envOr("UNIV4_NATIVE", 0x4200000000000000000000000000000000000006);
        token = vm.envOr("UNIV4_TOKEN", 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        fee = uint24(vm.envOr("UNIV4_FEE", uint256(500)));
        tickSpacing = int24(vm.envOr("UNIV4_TICK_SPACING", int256(10)));
        hooks = vm.envOr("UNIV4_HOOKS", address(0));
        amount = vm.envOr("UNIV4_AMOUNT", uint256(1 ether));

        if (forkBlock == 0) vm.createSelectFork(rpc);
        else vm.createSelectFork(rpc, forkBlock);
        swapper = new UniV4Swapper(permit2, router, native);
    }

    function test_swap_nativeIn() public {
        vm.deal(user, amount);

        vm.startPrank(user);
        IWrappedNative(native).deposit{value: amount}();
        IERC20(native).approve(address(swapper), amount);
        swapper.swap(address(0), token, amount, 0, _path(token));
        vm.stopPrank();

        assertApproxEqRel(IERC20(token).balanceOf(user), _quote(amount, true), 0.01e18, "token out vs pool price");
        assertEq(IERC20(native).balanceOf(user), 0);
        assertEq(router.balance, 0, "native left in router");
        _assertSwapperEmpty();
    }

    function test_swap_nativeOut() public {
        uint256 tokenAmount = _quote(amount, true);
        deal(token, user, tokenAmount);

        vm.startPrank(user);
        IERC20(token).approve(address(swapper), tokenAmount);
        swapper.swap(token, address(0), tokenAmount, 0, _path(address(0)));
        vm.stopPrank();

        assertApproxEqRel(IERC20(native).balanceOf(user), _quote(tokenAmount, false), 0.01e18, "native out vs pool price");
        assertEq(IERC20(token).balanceOf(user), 0);
        _assertSwapperEmpty();
    }

    function _path(address intermediate) internal view returns (UniV4Swapper.PathKey[] memory path) {
        path = new UniV4Swapper.PathKey[](1);
        path[0] = UniV4Swapper.PathKey(intermediate, fee, tickSpacing, hooks, "");
    }

    /// @dev Spot-price quote less the LP fee (impact ignored; callers allow 1%).
    ///      Native is always currency0 as address(0) sorts first.
    function _quote(uint256 amountIn, bool nativeIn) internal view returns (uint256) {
        bytes32 poolId = keccak256(abi.encode(address(0), token, fee, tickSpacing, hooks));
        uint256 slot0 = uint256(IExtsload(IUniversalRouter(router).poolManager()).extsload(keccak256(abi.encode(poolId, POOLS_SLOT))));
        uint256 p = uint160(slot0);
        require(p != 0, "pool not initialized");
        uint256 lpFee = uint24(slot0 >> 208);

        uint256 out = nativeIn ? amountIn * p / 2 ** 96 * p / 2 ** 96 : amountIn * 2 ** 96 / p * 2 ** 96 / p;
        return out * (1e6 - lpFee) / 1e6;
    }

    function _assertSwapperEmpty() internal view {
        assertEq(address(swapper).balance, 0, "swapper native");
        assertEq(IERC20(native).balanceOf(address(swapper)), 0, "swapper wrapped native");
        assertEq(IERC20(token).balanceOf(address(swapper)), 0, "swapper token");
    }
}
