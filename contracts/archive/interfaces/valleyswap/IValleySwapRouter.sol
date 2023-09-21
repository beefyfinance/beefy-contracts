// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IValleySwapRouter {
    function factory() external view returns (address);
    function WROSE() external view returns (address);

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
    function addLiquidityROSE(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountROSE, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityROSE(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountROSE);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityROSEWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountROSE);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactROSEForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactROSE(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForROSE(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapROSEForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function addLiquiditySupportingFeeOnTransfer(
        address feeToken,
        address tokenB,
        uint amountFeeTokenDesired,
        uint amountBDesired,
        uint amountFeeTokenMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountFeeToken, uint amountB, uint liquidity);

    function removeLiquidityROSESupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline
    ) external returns (uint amountROSE);
    function removeLiquidityROSEWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountROSEMin,
        address to,
        uint deadline, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountROSE);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactROSEForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForROSESupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}