// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGasPrice {
    function maxGasPrice() external returns (uint);
}