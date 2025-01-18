// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEqualizerRewardPool {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward(address user, address[] memory rewards) external;
    function getReward() external;
    function earned(address token, address user) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function stake() external view returns (address);
}
