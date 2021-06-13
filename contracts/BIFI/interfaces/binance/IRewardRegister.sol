// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IRewardRegister {
    function registerContract(address contractAddr, address payable rewardAddr, string calldata url) external returns (bool);
}