// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IForReward {
    function claimReward() external;
    function checkBalance(address account) external view returns (uint256);
}