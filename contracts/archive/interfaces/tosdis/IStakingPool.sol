// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IStakingPool {
    function stakeTokens(uint256 amount) external;
    function withdrawStake(uint256 amount) external;
    function emergencyWithdraw() external;
    function getUserInfo(address user) external view returns (uint256, uint256);
}
