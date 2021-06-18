// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IIncentivesController {
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
}