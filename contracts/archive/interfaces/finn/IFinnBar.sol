// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IFinnBar {
  function deposit(uint256 _amount) external;
  function withdraw(uint256 _share) external;
}
