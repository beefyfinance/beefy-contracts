// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IGasPrice {
    function maxGasPrice() external returns (uint);
}