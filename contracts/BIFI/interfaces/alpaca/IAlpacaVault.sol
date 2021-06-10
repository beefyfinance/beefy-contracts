// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IAlpacaVault {
  function deposit(uint256 amountToken) external payable;
  function withdraw(uint256 share) external;
}