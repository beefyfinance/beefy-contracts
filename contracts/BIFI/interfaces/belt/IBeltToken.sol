// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBeltToken {
    function token() external view returns (address);
    function deposit(uint256 amount, uint256 min_mint_amount) external;
}