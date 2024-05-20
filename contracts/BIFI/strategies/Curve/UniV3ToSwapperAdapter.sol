// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/common/IUniswapRouterV3WithDeadline.sol";
import "../../utils/UniswapV3Utils.sol";

contract UniV3ToSwapperAdapter {
    using SafeERC20 for IERC20;

    address public swapper;

    constructor(address _swapper) {
        swapper = _swapper;
    }

    function exactInput(IUniswapRouterV3WithDeadline.ExactInputParams calldata params) external payable returns (uint amountOut) {
        address[] memory route = UniswapV3Utils.pathToRoute(params.path);
        address from = route[0];
        address to = route[route.length - 1];
        IERC20(from).safeTransferFrom(msg.sender, address(this), params.amountIn);
        IERC20(from).forceApprove(swapper, params.amountIn);
        amountOut = IBeefySwapper(swapper).swap(from, to, params.amountIn);
        IERC20(to).safeTransfer(msg.sender, amountOut);
    }
}