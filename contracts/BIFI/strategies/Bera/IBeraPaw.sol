// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBeraPaw {
    function mint(address user, address rewardVault, address recipient) external returns (uint256);
}

