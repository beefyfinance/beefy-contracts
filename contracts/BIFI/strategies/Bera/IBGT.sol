// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBGT {
    function balanceOf(address) external view returns (uint256);
    function redeem(address receiver, uint256 amount) external;
}