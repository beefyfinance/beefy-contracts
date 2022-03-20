// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IERC20Like {

    function approve(address spender_, uint256 amount_) external;

    function balanceOf(address account_) external view returns (uint256 balance_);
}