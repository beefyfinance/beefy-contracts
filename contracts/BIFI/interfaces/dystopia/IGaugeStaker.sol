// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGaugeStaker { 
    function deposit(address gauge, uint amount) external;
    function withdraw(address gauge, uint amount) external;
    function harvestRewards(address gauge, address[] calldata tokens) external;
}