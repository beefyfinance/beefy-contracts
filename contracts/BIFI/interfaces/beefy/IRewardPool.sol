// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IRewardPool {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function balanceOf(address account) external view returns (uint256);
}
