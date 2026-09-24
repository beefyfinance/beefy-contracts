// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IKodiakIsland {
    function pool() external view returns (address);
    function getUnderlyingBalances() external view returns (uint amount0Current, uint amount1Current);
    function getMintAmounts(uint amount0Max, uint amount1Max) external view returns (uint amount0, uint amount1, uint mintAmount);
    function mint(uint mintAmount, address receiver) external returns (uint amount0, uint amount1, uint128 liquidityMinted);
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

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint32, bool);
    function token0() external view returns (address);
    function token1() external view returns (address);
}