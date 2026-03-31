// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBeefyVaultConcLiq {
    function previewDeposit(uint256 _amount0, uint256 _amount1) external view returns (uint256 shares, uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1);
    function previewWithdraw(uint256 shares) external view returns (uint256 amount0, uint256 amount1);
    function strategy() external view returns (address);
    function totalSupply() external view returns (uint256);
    function wants() external view returns (address, address);
    function balances() external view returns (uint256, uint256);
    function deposit(uint256 amount0, uint256 amount1, uint256 minShares) external;
    function isCalm() external view returns (bool);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}