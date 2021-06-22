// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IGovMothership {
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
}
