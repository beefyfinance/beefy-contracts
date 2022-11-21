// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

interface ITridentRouter {
    struct Path {
        address pool;
        bytes data;
    }

    struct ExactInputParams {
        address tokenIn;
        uint256 amountIn;
        uint256 amountOutMinimum;
        Path[] path;
    }

    struct ExactInputSingleParams {
        uint256 amountIn;
        uint256 amountOutMinimum;
        address pool;
        address tokenIn;
        bytes data;
    }

    struct TokenInput {
        address token;
        bool native;
        uint256 amount;
    }

    function exactInputWithNativeToken(ExactInputParams calldata params) external returns (uint256 amountOut);

    function exactInputSingleWithNativeToken(
        ExactInputSingleParams calldata params
    ) external returns (uint256 amountOut);

    function addLiquidity(
        TokenInput[] calldata tokenInput,
        address pool,
        uint256 minLiquidity,
        bytes calldata data
    ) external returns (uint256 liquidity);

    function bento() external view returns (address);
}