// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IHelper {
    function claimRewards(address _gauge, address _user) external;
}