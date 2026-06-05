// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IeQI {
    function enter(uint256 _amount, uint256 _block) external;
    function emergencyExit() external;
    function Qi() external view returns (address);
    function userInfo(address _user) external view returns (uint256, uint256);
    function balanceOf(address _user) external view returns (uint256);
}