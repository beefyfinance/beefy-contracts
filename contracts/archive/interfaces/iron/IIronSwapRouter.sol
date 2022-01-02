// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IIronSwapRouter {
    function addLiquidity(
        address pool,
        address basePool,
        uint256[] memory meta_amounts,
        uint256[] memory base_amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256);
}