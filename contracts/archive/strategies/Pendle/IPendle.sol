// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IPendleMarket {
    function redeemRewards(address user) external returns (uint256[] memory);
    function userReward(address user, address reward) external returns (uint128 index, uint128 accrued);
    function rewardState(address reward) external returns (uint128 index, uint128 accrued);
    function activeBalance(address user) external returns (uint bal);
}