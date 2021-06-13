// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IForReward {
    function claimReward() external;
    function checkBalance(address account) external view returns (uint256);
}