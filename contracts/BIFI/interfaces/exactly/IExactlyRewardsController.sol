// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IExactlyRewardsController {
    function claimAll(address to) external returns (address[] memory rewardList, uint256[] memory claimedAmounts);

    function allClaimable(
        address account,
        address reward
    ) external view returns (uint256 unclaimedRewards);
}