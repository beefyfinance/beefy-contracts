// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

interface ICurveSwap {
    function remove_liquidity_one_coin(uint256 token_amount, int128 i, uint256 min_amount) external;
    function calc_withdraw_one_coin(uint256 tokenAmount, int128 i) external view returns (uint256);
    function coins(uint256 arg0) external view returns (address);

    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external payable;
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount, bool _use_underlying) external;
    function add_liquidity(address _pool, uint256[2] memory amounts, uint256 min_mint_amount) external;

    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external payable;
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount, bool _use_underlying) external payable;
    function add_liquidity(address _pool, uint256[3] memory amounts, uint256 min_mint_amount) external payable;

    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount) external payable;
    function add_liquidity(address _pool, uint256[4] memory amounts, uint256 min_mint_amount) external payable;

    function add_liquidity(uint256[5] memory amounts, uint256 min_mint_amount) external payable;
    function add_liquidity(address _pool, uint256[5] memory amounts, uint256 min_mint_amount) external payable;

    function add_liquidity(uint256[6] memory amounts, uint256 min_mint_amount) external payable;
    function add_liquidity(address _pool, uint256[6] memory amounts, uint256 min_mint_amount) external payable;

    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external;
}