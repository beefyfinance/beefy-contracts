// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";

import { IUniswapRouterETH } from "../../interfaces/common/IUniswapRouterETH.sol";
import { IBeefySwapper } from "../../interfaces/beefy/IBeefySwapper.sol";

contract SwapBasedUnirouter is Ownable {
    using SafeERC20 for IERC20;

    IBeefySwapper public swapper;
    IUniswapRouterETH public swapBasedRouter;

    constructor(address _swapper, address _swapBasedRouter) {
        swapper = IBeefySwapper(_swapper);
        swapBasedRouter = IUniswapRouterETH(_swapBasedRouter);
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = IBeefySwapper(_swapper);
    }

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 /*_minAmountOut*/,
        address[] calldata _route,
        address _receiver,
        uint256 /*_deadline*/
    ) external returns (uint256[] memory) {
        address from = _route[0];
        address to = _route[_route.length - 1];

        IERC20(from).safeTransferFrom(msg.sender, address(this), _amountIn);
        IERC20(from).safeApprove(address(swapper), 0);
        IERC20(from).safeApprove(address(swapper), _amountIn);
        swapper.swap(from, to, _amountIn);
        uint256 toBal = IERC20(to).balanceOf(address(this));
        IERC20(to).safeTransfer(_receiver, toBal);

        uint256[] memory amounts = new uint256[](_route.length);
        ( amounts[0], amounts[amounts.length - 1] ) = ( _amountIn, toBal );
        return amounts;
    }

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint _amountADesired,
        uint _amountBDesired,
        uint _amountAMin,
        uint _amountBMin,
        address _to,
        uint _deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        IERC20(_tokenA).safeTransferFrom(msg.sender, address(this), _amountADesired);
        IERC20(_tokenA).safeApprove(address(swapBasedRouter), 0);
        IERC20(_tokenA).safeApprove(address(swapBasedRouter), _amountADesired);

        IERC20(_tokenB).safeTransferFrom(msg.sender, address(this), _amountBDesired);
        IERC20(_tokenB).safeApprove(address(swapBasedRouter), 0);
        IERC20(_tokenB).safeApprove(address(swapBasedRouter), _amountBDesired);

        (amountA, amountB, liquidity) = swapBasedRouter.addLiquidity(
            _tokenA,
            _tokenB,
            _amountADesired,
            _amountBDesired,
            _amountAMin,
            _amountBMin,
            _to,
            _deadline
        );

        uint256 tokenABal = IERC20(_tokenA).balanceOf(address(this));
        if (tokenABal > 0) IERC20(_tokenA).safeTransfer(_to, tokenABal);
        uint256 tokenBBal = IERC20(_tokenB).balanceOf(address(this));
        if (tokenBBal > 0) IERC20(_tokenB).safeTransfer(_to, tokenBBal);
    }

    function getAmountsOut(
        uint _amountIn,
        address[] calldata _route
    ) external view returns (uint[] memory) {
        uint256 amountOut = swapper.getAmountOut(_route[0], _route[_route.length - 1], _amountIn);
        uint256[] memory amountsOut = new uint256[](_route.length);
        amountsOut[amountsOut.length - 1] = amountOut;
        return amountsOut;
    }
}
