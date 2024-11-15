// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGnsStaking {
    function stakeGns(uint128 _amountGns) external;
    function unstakeGns(uint128 _amountGns) external;
    function harvestTokens() external;
    function stakers(address _user) external view returns (uint128 stakedGns, uint128 debtDai);
    function pendingRewardToken(address _user, address _rewardToken) external view returns (uint128);
}
