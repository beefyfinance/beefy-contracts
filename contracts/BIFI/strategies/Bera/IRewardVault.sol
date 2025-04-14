// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRewardVault {
    function balanceOf(address) external view returns (uint256);
    function earned(address) external view returns (uint256);
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward(address account, address recipient) external returns (uint256);
    function setOperator(address _operator) external;
}