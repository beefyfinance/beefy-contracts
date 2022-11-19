// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFerroBoost {
    struct Stake {
        uint256 amount;
        uint256 poolId;
        uint256 weightedAmount;
        uint256 stakeTimestamp;
        uint256 unlockTimestamp;
        bool active;
    }
    function withdraw(uint256 stakeId) external;
    function batchWithdraw(uint256[] memory stakeIds) external;
    function getUserStake(address user, uint256 stakeId) external view returns (Stake memory);
}