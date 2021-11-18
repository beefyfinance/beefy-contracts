// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IFarm {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function pending(uint256 _pid, address _to) external view returns (uint256);
}