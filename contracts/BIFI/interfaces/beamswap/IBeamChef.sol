// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBeamChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256, uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function pendingTokens(uint256 pid, address user) external view returns (address[] memory, string memory, uint256[] memory, uint256[] memory);
}