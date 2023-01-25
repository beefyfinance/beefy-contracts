// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IRewardToken {
    function getReward() external;
    function minter() external view returns (address);
}