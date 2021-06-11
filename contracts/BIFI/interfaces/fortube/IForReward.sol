// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IForReward {
    function claimReward() external;
    function checkBalance(address account) external view returns (uint256);
}