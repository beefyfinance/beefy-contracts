// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IQlpTracker {
    function claimable(address user, address reward) external view returns (uint256);
}
