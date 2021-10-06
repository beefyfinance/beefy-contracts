// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IIncentivesController {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);
}