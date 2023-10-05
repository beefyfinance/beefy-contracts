// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBeefyOracle {
    function getPrice(address token) external view returns (uint256 price);
    function getPrice(address[] calldata tokens) external view returns (uint256[] memory prices);
    function getFreshPrice(address token) external returns (uint256 price, bool success);
    function getFreshPrice(address[] calldata tokens) external returns (uint256[] memory prices, bool[] memory successes);
}
