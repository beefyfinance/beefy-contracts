// SPDX-License-Identifier: MIT

pragma solidity >0.6.0;

interface IRewarder {
    function poolLength() external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function pendingToken(uint256 _pid, address _user) external view returns (uint256);
    function deposit(uint256 pid, uint256 amount, address to) external;
    function withdraw(uint256 pid, uint256 amount, address to) external;
    function harvest(uint256 pid, address to) external;
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;
    function emergencyWithdraw(uint256 pid, address to) external;
} 