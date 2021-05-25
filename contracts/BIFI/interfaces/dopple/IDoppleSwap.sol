// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IDoppleSwap {
    function getTokenIndex(address tokenAddress) external view returns (uint8);
    function addLiquidity(uint256[] calldata amounts, uint256 minToMint, uint256 deadline) external returns (uint256);
}