// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IVeJoeStaker {
    function deposit(address _chef, uint256 _pid, uint256 _amount) external;
    function withdraw(address _chef, uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(address _chef, uint256 _pid) external;
    function upgradeStrategy(address _chef, uint256 _pid) external;
}