// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IStableSwapAave {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount, bool _use_underlying) external;
}