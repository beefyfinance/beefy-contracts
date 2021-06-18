// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IRewardRegister {
    function registerContract(address contractAddr, address payable rewardAddr, string calldata url) external returns (bool);
}