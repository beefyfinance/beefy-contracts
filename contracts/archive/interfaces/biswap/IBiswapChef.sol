// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBiswapChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function pendingBSW(uint256 _pid, address _user) external view returns (uint256);
    function migrator() external view returns (address);
}