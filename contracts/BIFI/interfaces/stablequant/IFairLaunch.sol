// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IFairLaunch {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingQuant(uint256 _pid, address _user) external view returns (uint256);
    function withdrawAll(uint256 _pid) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256, uint256, address);
    function emergencyWithdraw(uint256 _pid) external;
    function harvest(uint256 _pid) external;
}