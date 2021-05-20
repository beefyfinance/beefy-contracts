// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IMultiFeeDistribution {
    function totalBalance(address user) view external returns (uint256);
    function stake(uint256 amount, bool lock) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
}