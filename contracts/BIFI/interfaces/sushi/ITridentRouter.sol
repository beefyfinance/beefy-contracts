// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

interface ITridentRouter {
    struct Path {
        address pool;
        bytes data;
    }
    struct ExactInputSingleParams {
        uint256 amountIn;
        uint256 amountOutMinimum;
        address pool;
        address tokenIn;
        bytes data;
    }
    function exactInputSingleWithNativeToken(
        ExactInputSingleParams calldata params
    ) external returns (uint256 amountOut);
}