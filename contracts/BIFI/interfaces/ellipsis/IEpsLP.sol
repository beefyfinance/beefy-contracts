// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IEpsLP {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external;
}