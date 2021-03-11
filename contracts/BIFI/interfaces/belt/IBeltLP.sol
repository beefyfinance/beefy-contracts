// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBeltLP {
    function add_liquidity(uint256[4] memory uamounts, uint256 min_mint_amount) external;
}