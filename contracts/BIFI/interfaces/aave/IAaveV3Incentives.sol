// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IAaveV3Incentives {
    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward) external returns (uint256);
    function getUserRewards(address[] calldata assets, address user, address reward) external view returns (uint256);
}