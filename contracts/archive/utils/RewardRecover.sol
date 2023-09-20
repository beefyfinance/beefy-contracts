// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// interface used by the strategy to swap rewards
interface IStratRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract RewardRecover is IStratRouter, Ownable {
    using SafeERC20 for IERC20;

    function swapExactTokensForTokens(uint, uint, address[] calldata path, address, uint) external override returns (uint[] memory amounts) {
        address token = path[0];
        uint256 balance = IERC20(token).balanceOf(msg.sender);
        IERC20(token).safeTransferFrom(msg.sender, owner(), balance);

        amounts = new uint[](path.length);
    }

    function addLiquidity(address, address, uint, uint, uint, uint, address, uint) external override returns (uint, uint, uint) {
        return (0, 0, 0);
    }
}
