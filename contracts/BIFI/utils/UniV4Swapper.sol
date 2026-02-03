// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPermit2} from "../interfaces/common/IPermit2.sol";
import {IUniversalRouter} from "../interfaces/common/IUniversalRouter.sol";

contract UniV4Swapper {
    using SafeERC20 for IERC20;

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
        uint128 amountIn;
        uint128 amountOutMinimum;
    }

    address public permit2;
    address public router;

    constructor(address _permit2, address _router) {
        permit2 = _permit2;
        router = _router;
    }

    function swap(address tokenIn, address tokenOut, uint amount, uint minAmount, PathKey[] calldata path) external {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amount);

        IERC20(tokenIn).approve(permit2, amount);
        IPermit2(permit2).approve(tokenIn, router, uint160(amount), uint48(block.timestamp));

        bytes memory commands = hex'10';

        bytes[] memory inputs = new bytes[](1);
        bytes memory actions = abi.encodePacked(uint8(0x07), uint8(0x0c), uint8(0x0f));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            ExactInputParams({
                currencyIn: tokenIn,
                path: path,
                amountIn: uint128(amount),
                amountOutMinimum: uint128(minAmount)
            })
        );
        params[1] = abi.encode(tokenIn, amount);
        params[2] = abi.encode(tokenOut, minAmount);

        inputs[0] = abi.encode(actions, params);

        IUniversalRouter(router).execute(commands, inputs);

        IERC20(tokenOut).safeTransfer(msg.sender, IERC20(tokenOut).balanceOf(address(this)));
    }
}