// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITokemakRewarder {
    function stake(address _account, uint256 _amount) external;
    function withdraw(address account, uint256 amount, bool claim) external;
    function balanceOf(address _account) external view returns (uint256);
    function getReward() external;
    function stakingToken() external view returns (address);
    function rewardToken() external view returns (address);
}
