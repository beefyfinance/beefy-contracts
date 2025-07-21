// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";

interface IBeefyVault is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function want() external pure returns (address); // Beefy Vault V6
    function token() external pure returns (address); // Beefy Vault V5
    function balance() external pure returns (uint256);
    function totalSupply() external pure returns (uint256);
    function strategy() external pure returns (address);
}