// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

interface IGrailToken {

  function unwrap(uint256 amount) external;
  function getExpectedUnwrappedTokenAmount(address account, uint256 amount) external view returns (uint256);
}
