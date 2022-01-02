// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IUnipool {
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimReward() external;
}