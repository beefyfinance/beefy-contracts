// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBeefyDataSource {
    function feeData(address factory) external view returns (uint rootKInteger, uint rootKLastInteger);
    function isSolidPair(address factory) external view returns (bool);
}