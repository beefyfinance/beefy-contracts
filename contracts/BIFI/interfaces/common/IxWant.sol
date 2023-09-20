// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IxWant {
  function enter(uint256 _amount) external;
  function leave(uint256 _share) external;
  function totalSupply() external view returns (uint256);
  function stella() external view returns (address);
}