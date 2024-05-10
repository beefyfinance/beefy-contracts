// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISwapBasedOption {
    function instantExit(uint256 _amount, uint256 maxPayAmount) external;
    function quotePayment(uint256 amount) external view returns (uint256 payAmount);
    function quotePrice(uint256 amountIn) external view returns (uint256 amountOut);
}