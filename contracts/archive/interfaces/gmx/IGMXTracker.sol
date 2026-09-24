// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGMXTracker {
    function claim(address receiver) external;
    function claimable(address user) external view returns (uint256);
    function depositBalances(address user, address token) external view returns (uint256);
    function stakedAmounts(address user) external view returns (uint256);
}
