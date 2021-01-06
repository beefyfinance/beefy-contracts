// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ISmartChef {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function pendingReward(address _user) external view returns (uint256);
    function userInfo(address _user) external view returns (uint256, uint256);
    function emergencyWithdraw() external;
    function rewardToken() external view returns (address);
}