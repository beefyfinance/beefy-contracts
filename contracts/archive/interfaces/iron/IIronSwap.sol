// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IIronSwap {
    function getNumberOfTokens() external view returns (uint256);
    function getToken(uint8 index) external view returns (address);
    function addLiquidity(uint256[] memory amounts, uint256 minMintAmount, uint256 deadline) external returns (uint256);
}