// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IRewardRegister {
    function registerContract(address contractAddr, address payable rewardAddr) external returns (bool);
}