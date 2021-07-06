// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IStableSwapAave {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount, bool _use_underlying) external;
}

interface IStableSwapAave2 {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount, bool _use_underlying) external;
}