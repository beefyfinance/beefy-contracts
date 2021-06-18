// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IGovMothership {
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
}
