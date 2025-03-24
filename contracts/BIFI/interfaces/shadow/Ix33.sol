// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface Ix33 {
    function deposit(uint256 assets, address receiver) external;
    function convertToShares(uint256 assets) external view returns (uint256);
}
