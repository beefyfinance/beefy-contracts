// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IQlpManager {
    function lastAddedAt(address _user) external view returns (uint256);
    function cooldownDuration() external view returns (uint256);
}
