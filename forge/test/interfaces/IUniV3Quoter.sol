// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniV3Quoter {

    function quoteExactInput(bytes memory path, uint256 amountIn) external returns (uint256 amountOut);
}