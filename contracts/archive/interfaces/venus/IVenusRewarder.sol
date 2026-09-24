// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVenusRewarder {
    function rewardToken() external view returns (address);
    function claimRewardToken(address holder, address[] memory iTokens) external;
}
