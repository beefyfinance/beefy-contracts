// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface ICurveSwap256 {
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external;
}