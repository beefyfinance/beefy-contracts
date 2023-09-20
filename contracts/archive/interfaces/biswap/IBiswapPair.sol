// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBiswapPair {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swapFee() external view returns (uint32);
    function burn(address to) external returns (uint amount0, uint amount1);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}