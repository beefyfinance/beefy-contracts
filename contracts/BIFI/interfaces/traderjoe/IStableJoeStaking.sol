// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IStableJoeStaking {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function emergencyWithdraw() external;
    function pendingReward(address _user, address _token) external view returns (uint256);
    function getUserInfo(address _user, address _rewardToken) external view returns (uint256, uint256);
}
