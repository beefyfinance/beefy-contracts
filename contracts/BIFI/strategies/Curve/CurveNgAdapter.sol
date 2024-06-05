// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";

// NG pools use dynamic arrays not compatible with curveRouter-v1.0
// this contract adapts add_liquidity(uint256[2] amounts) to add_liquidity(uint256[] amounts)

interface CurveStableSwapNg {
    function add_liquidity(uint256[] memory _amounts, uint256 _min_mint_amount, address _receiver) external returns (uint256);
    function coins(uint i) external view returns (address);
}

contract CurveNgAdapter {

    CurveStableSwapNg public pool;
    IERC20 public t0;
    IERC20 public t1;

    constructor(address _pool) {
        pool = CurveStableSwapNg(_pool);
        t0 = IERC20(pool.coins(0));
        t1 = IERC20(pool.coins(1));
        t0.approve(_pool, type(uint).max);
        t1.approve(_pool, type(uint).max);
    }

    function add_liquidity(uint256[2] memory _amounts, uint256 min_mint_amount) external {
        uint[] memory amounts = new uint[](2);
        amounts[0] = _amounts[0];
        amounts[1] = _amounts[1];
        if (amounts[0] > 0) t0.transferFrom(msg.sender, address(this), amounts[0]);
        if (amounts[1] > 0) t1.transferFrom(msg.sender, address(this), amounts[1]);
        CurveStableSwapNg(pool).add_liquidity(amounts, min_mint_amount, msg.sender);
    }
}