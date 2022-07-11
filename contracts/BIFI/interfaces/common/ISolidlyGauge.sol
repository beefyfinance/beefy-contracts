// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ISolidlyGauge {
    function deposit(uint256 amount, uint256 tokenId) external;
    function withdraw(uint256 amount) external;
    function getReward(address user, address[] memory rewards) external;
    function earned(address token, address user) external view returns (uint256);
    function balanceOf(address user) external view returns (uint256);
}
