// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ICurveSwap2 {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external;
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount, bool _use_underlying) external;
}

interface ICurveSwap3 {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external;
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount, bool _use_underlying) external;
}

interface ICurveSwap4 {
    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount) external;
}

interface ICurveSwap5 {
    function add_liquidity(uint256[5] memory amounts, uint256 min_mint_amount) external;
}