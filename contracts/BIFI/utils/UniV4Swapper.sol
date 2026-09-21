// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {SafeERC20, IERC20} from "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin-5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPermit2} from "../interfaces/common/IPermit2.sol";
import {IUniversalRouter} from "../interfaces/common/IUniversalRouter.sol";
import {IWrappedNative} from "../interfaces/common/IWrappedNative.sol";

/// @notice Swapper for Uniswap Universal Router v2.1.1 V4 swaps.
/// @author kexley, chimp, jackgale.eth, Beefy
/// @dev V2.1.1 expects `minHopPriceX36` in `ExactInputParams`; older UniV4Swapper versions are not compatible.
contract UniV4Swapper {
    using SafeERC20 for IERC20;

    error InvalidEthSender();
    error InvalidNativeTokenDecimals(uint8 decimals);
    error AmountTooLarge(uint amount);

    struct PathKey {
        address intermediateCurrency;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        bytes hookData;
    }

    struct ExactInputParams {
        address currencyIn;
        PathKey[] path;
        uint256[] minHopPriceX36;
        uint128 amountIn;
        uint128 amountOutMinimum;
    }

    address public permit2;
    address public router;
    address public native;
    bool public nativeIsMirrored;
    uint public nativeScale;

    constructor(address _permit2, address _router, address _native, bool _nativeIsMirrored) {
        permit2 = _permit2;
        router = _router;
        native = _native;
        nativeIsMirrored = _nativeIsMirrored;

        if (_nativeIsMirrored) {
            uint8 decimals = IERC20Metadata(_native).decimals();
            if (decimals > 18) revert InvalidNativeTokenDecimals(decimals);
            nativeScale = 10 ** (18 - decimals);
        } else {
            nativeScale = 1;
        }
    }

    /// @notice Swap along a v4 path
    /// @dev Amounts are always in the decimals of the ERC20 the caller pays or receives (not native)
    /// @param tokenIn Token swapped from, or address(0) to pay the native currency, taken as ERC20 `native`.
    /// @param tokenOut Token swapped to, or address(0) to receive the native currency, paid as ERC20 `native`.
    /// @param amount Amount of tokenIn to swap, in tokenIn's decimals (ERC20 `native`'s for address(0)).
    /// @param minAmount Minimum tokenOut to accept, in tokenOut's decimals (ERC20 `native`'s for address(0)).
    /// @param path Currencies to swap through, after tokenIn.
    function swap(address tokenIn, address tokenOut, uint amount, uint minAmount, PathKey[] calldata path) external {
        uint routerAmount = _toRouterUnits(tokenIn, amount);
        uint routerMinAmount = _toRouterUnits(tokenOut, minAmount);

        _receiveInput(tokenIn, amount);

        bytes memory commands = hex'10'; // V4_SWAP
        bytes[] memory inputs = new bytes[](1);
        bytes memory actions = abi.encodePacked(uint8(0x07), uint8(0x0c), uint8(0x0f)); // SWAP_EXACT_IN, SETTLE_ALL, TAKE_ALL
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            ExactInputParams({
                currencyIn: tokenIn,
                path: path,
                minHopPriceX36: new uint256[](0),
                amountIn: uint128(routerAmount),
                amountOutMinimum: uint128(routerMinAmount)
            })
        );
        params[1] = abi.encode(tokenIn, routerAmount);
        params[2] = abi.encode(tokenOut, routerMinAmount);
        inputs[0] = abi.encode(actions, params);

        IUniversalRouter(router).execute{value: tokenIn == address(0) ? routerAmount : 0}(commands, inputs);

        _payOutput(tokenOut);
    }

    /// @dev Pulls the input from the caller. Callers always pay in ERC20, so for a native tokenIn it
    ///      is `native` that is pulled, then unwrapped unless it already mirrors the gas token. Any
    ///      other tokenIn is pulled as-is and approved to the router through permit2.
    function _receiveInput(address tokenIn, uint amount) private {
        if (tokenIn == address(0)) {
            IERC20(native).safeTransferFrom(msg.sender, address(this), amount);
            if (!nativeIsMirrored) IWrappedNative(native).withdraw(amount);
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(tokenIn).forceApprove(permit2, amount);
            IPermit2(permit2).approve(tokenIn, router, uint160(amount), uint48(block.timestamp));
        }
    }

    /// @dev Sends the whole output balance to the caller, likewise always as ERC20: native output is
    ///      paid as `native`, wrapping it first unless it already mirrors the gas token.
    function _payOutput(address tokenOut) private {
        if (tokenOut == address(0)) {
            if (!nativeIsMirrored) IWrappedNative(native).deposit{value: address(this).balance}();
            IERC20(native).safeTransfer(msg.sender, IERC20(native).balanceOf(address(this)));
        } else {
            IERC20(tokenOut).safeTransfer(msg.sender, IERC20(tokenOut).balanceOf(address(this)));
        }
    }

    /// @dev Converts an amount from caller units to router units, in native wei for the native currency.
    function _toRouterUnits(address token, uint amount) private view returns (uint routerAmount) {
        routerAmount = token == address(0) ? amount * nativeScale : amount;
        if (routerAmount > type(uint128).max) revert AmountTooLarge(routerAmount);
    }

    receive() external payable {
        if (msg.sender != address(native) && msg.sender != address(IUniversalRouter(router).poolManager())) revert InvalidEthSender();
    }
}
