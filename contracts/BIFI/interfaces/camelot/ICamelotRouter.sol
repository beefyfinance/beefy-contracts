// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICamelotRouter {
  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    address referrer,
    uint256 deadline
  ) external;
  function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}
