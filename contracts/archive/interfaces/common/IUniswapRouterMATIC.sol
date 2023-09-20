// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IUniswapRouterMATIC {
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

    function addLiquidityMATIC(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountMATICMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountMATIC, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function removeLiquidityMATIC(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMATICMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountMATIC);

    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapExactMATICForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    
    function swapExactTokensForMATIC(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
}