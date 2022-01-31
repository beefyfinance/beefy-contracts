// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IXPool {
    function getShareValue() external returns (uint256);
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
}
