// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEpsLP {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external;
}