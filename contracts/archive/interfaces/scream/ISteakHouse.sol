// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ISteakHouse {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;
    function getUserInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function depositFee() external view returns (uint256);
}