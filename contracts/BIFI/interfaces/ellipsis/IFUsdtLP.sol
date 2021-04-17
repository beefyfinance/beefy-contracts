// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IFUsdtLP {
    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount) external;
}