// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ICraftsmanV2 {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function pendingVVS(uint256 _pid, address _user) external view returns (uint256);
    function poolRewarders(uint256 _pid) external view returns (address[] memory rewarders);
}