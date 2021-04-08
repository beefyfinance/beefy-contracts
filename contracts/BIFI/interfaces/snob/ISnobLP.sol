// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ISnobLP {

//    function add_liquidity(uint256[4] memory uamounts, uint256 min_mint_amount) external;
    function addLiquidity(uint256[] calldata amounts, uint256 minToMint, uint256 deadline) external returns (uint256);
}