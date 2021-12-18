// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IBar {
  function enter(uint256 _amount) external;
  function leave(uint256 _share) external;
}
