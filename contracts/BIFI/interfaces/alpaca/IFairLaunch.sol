// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IFairLaunch {
    function deposit(address _for, uint256 _pid, uint256 _amount) external;
    function withdraw(address _for, uint256 _pid, uint256 _amount) external;
    function pendingAlpaca(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function harvest(uint256 _pid) external;
}