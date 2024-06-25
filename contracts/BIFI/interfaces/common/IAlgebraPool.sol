// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAlgebraPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getTimepoints(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulatives,
            uint112[] memory volatilityCumulatives,
            uint256[] memory volumePerAvgLiquiditys
        );
}