// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IGondolaSwap {
    function getToken(uint8 index) external view returns (address);
    function addLiquidity(uint256[] calldata amounts, uint256 minToMint, uint256 deadline) external returns (uint256);

}