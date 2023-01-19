// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategy {
    function withdrawalFee() external view returns (uint256);
    function unirouter() external view returns (address);
    function routerPoolId() external view returns (uint256);
    function stargateRouter() external view returns (address);
    function depositToken() external view returns (address);
    function stableRouter() external view returns (address);
    function depositIndex() external view returns (uint256);
}