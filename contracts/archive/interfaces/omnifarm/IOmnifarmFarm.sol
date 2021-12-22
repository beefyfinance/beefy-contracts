// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IOmnifarmFarm {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function emergencyWithdraw() external;
    function userInfo(address user) external view returns (uint256, uint256);
}
