// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGLPManager {
    function vault() external view returns (address);
    function getAumInUsdg(bool _maximise) external view returns (uint256);
    function lastAddedAt(address _user) external view returns (uint256);
    function cooldownDuration() external view returns (uint256);
}
