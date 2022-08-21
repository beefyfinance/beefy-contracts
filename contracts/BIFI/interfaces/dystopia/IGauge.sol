// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGauge { 
    function balanceOf(address user) external view returns (uint);
    function earned(address token, address user) external view returns (uint);
}