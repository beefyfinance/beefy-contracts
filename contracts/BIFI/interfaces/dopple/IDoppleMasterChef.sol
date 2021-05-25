// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IDoppleMasterChef {
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256, uint256, address);
    function deposit(address _for, uint256 _pid, uint256 _amount) external;
    function withdraw(address _for, uint256 _pid, uint256 _amount) external;
    function harvest(uint256 _pid) external;
    function emergencyWithdraw(uint256 _pid) external;
}