// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ICurveCryptoSwap {
    function add_liquidity(uint256[5] memory amounts, uint256 min_mint_amount) external;
}