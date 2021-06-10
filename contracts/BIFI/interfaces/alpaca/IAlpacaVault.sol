// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IAlpacaVault {
  function deposit(uint256 amountToken) external payable;
  function withdraw(uint256 share) external;
}