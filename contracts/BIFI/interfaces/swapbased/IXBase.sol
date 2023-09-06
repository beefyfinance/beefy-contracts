// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IXBase {
    function userPositions(address user) external view returns (uint256);
    function remainTime(address user, uint256 vestId) external view returns (uint256);
    function claim(uint256 vestId) external;
    function vestHalf(uint256 amount) external;
}