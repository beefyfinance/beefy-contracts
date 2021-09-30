// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IDeepFryer {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingFries(uint256 _pid, address _user) external view returns (uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint, uint);
}

