// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
    function getVault() external view returns (address);
}