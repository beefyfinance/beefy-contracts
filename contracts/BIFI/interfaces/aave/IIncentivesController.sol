// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IIncentivesController {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
}