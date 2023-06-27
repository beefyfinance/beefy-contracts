// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILpToken {
    function minter() external view returns (address);
}

interface IConicPool {
    function underlying() external view returns (address);
    function lpToken() external view returns (ILpToken);
    function rewardManager() external view returns (IRewardManager);
    function deposit(uint256 underlyingAmount, uint256 minLpReceived, bool stake) external returns (uint256);
    function withdraw(uint256 conicLpAmount, uint256 minUnderlyingReceived) external returns (uint256);
    function exchangeRate() external view returns (uint);
}

interface IRewardManager {
    function claimableRewards(
        address account
    ) external view returns (uint256 cncRewards, uint256 crvRewards, uint256 cvxRewards);
    function claimEarnings() external returns (uint256, uint256, uint256);
}

interface ILpTokenStaker {
    function stake(uint256 amount, address conicPool) external;
    function unstake(uint256 amount, address conicPool) external;
    function getUserBalanceForPool(address conicPool, address account) external view returns (uint256);
}