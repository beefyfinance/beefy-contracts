// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IWrappedGrand {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
}