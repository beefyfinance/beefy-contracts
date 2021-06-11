// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IRewardRegister {
    function registerContract(address contractAddr, address payable rewardAddr, string calldata url) external returns (bool);
}