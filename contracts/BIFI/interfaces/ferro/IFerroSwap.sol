// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFerroSwap {
    function addLiquidity(uint256[] memory amounts, uint256 minOut, uint256 deadline) external;
}