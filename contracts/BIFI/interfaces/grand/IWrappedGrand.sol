// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IWrappedGrand {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
}