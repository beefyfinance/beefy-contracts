// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IJoeChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
}