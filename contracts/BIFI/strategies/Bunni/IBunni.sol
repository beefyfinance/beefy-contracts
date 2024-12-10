// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBunniToken {
    function tickLower() external view returns (int24);
    function tickUpper() external view returns (int24);
    function totalSupply() external view returns (uint256);
    function pool() external view returns (address);
    function hub() external view returns (address);
}

interface IBunniHub {
    struct BunniKey {
        address pool;
        int24 tickLower;
        int24 tickUpper;
    }

    struct DepositParams {
        BunniKey key;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
        address recipient;
    }

    function deposit(DepositParams calldata params)
    external
    payable
    returns (
        uint256 shares,
        uint128 addedLiquidity,
        uint256 amount0,
        uint256 amount1
    );
}

interface IUniV3Pool {
    function positions(bytes32 key)
    external
    view
    returns (
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function token0() external view returns (address);
    function token1() external view returns (address);
}