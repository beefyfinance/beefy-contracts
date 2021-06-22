// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBakeryMaster {
    function deposit(address _pair, uint256 _amount) external;
    function withdraw(address _pair, uint256 _amount) external;
    function pendingBake(address _pair, address _user) external view returns (uint256);
    function poolUserInfoMap(address _pair, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(address _pair) external;
}