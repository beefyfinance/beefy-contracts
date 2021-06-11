// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IFor {
    function deposit(address token, uint256 amount) external payable;
    function withdraw(address underlying, uint256 withdrawTokens) external;
    function withdrawUnderlying(address underlying, uint256 amount) external;
    function controller() view external returns(address);
}