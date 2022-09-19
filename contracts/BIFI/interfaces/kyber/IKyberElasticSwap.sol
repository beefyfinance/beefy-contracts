// SPDX-License-Identifier: MIT

pragma solidity >0.6.0;

interface IKyberElasticSwap {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getPoolState() external view returns (
        uint160 sqrtP,
        int24 currentTick,
        int24 nearestCurrentTick,
        bool locked
    );
    function swap(
        address recipient,
        int256 swapQty,
        bool isToken0,
        uint160 limitSqrtP,
        bytes calldata data
    ) external returns (int256 deltaQty0, int256 deltaQty1);
}