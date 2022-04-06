// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBeethovenxChef {
    function deposit(uint256 _pid, uint256 _amount, address _to) external;
    function withdrawAndHarvest(uint256 _pid, uint256 _amount, address _to) external;
    function harvest(uint256 _pid, address _to) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid, address _to) external;
    function pendingBeets(uint256 _pid, address _to) external view returns (uint256);
    function rewarder(uint256 _pid) external view returns (address);
}