// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISimpleStaking {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimReward(address[] memory user) external;
    function userCollateral(address account) external view returns (uint256);
    function pendingReward(address user) external view returns (uint256);
}
