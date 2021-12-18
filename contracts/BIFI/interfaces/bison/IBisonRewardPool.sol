// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBisonRewardPool {
    function deposit(uint256 amount) external returns (bool);
    function withdraw(uint256 amount) external returns (bool);
    function pendingReward(address account) external view returns (uint256);
    function userInfo(address account) external view returns (uint256,uint256);
}
