// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISubOracle {
    function getPrice(bytes calldata data) external returns (uint256 price, bool success);
    function validateData(bytes calldata data) external view;
}