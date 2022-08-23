// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IJungleChef {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function userInfo(address _user) external view returns (uint256, uint256);
    function pendingReward(address _user) external view returns (uint256);
    function emergencyWithdraw() external;
}