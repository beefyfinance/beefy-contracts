// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface ISolaceRewards {
    function harvestLock(uint256 xsLockID) external;
    function pendingRewardsOfLock(uint256 xsLockID) external view returns (uint256 reward);
}