// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IExactlyMarket {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function borrow(uint256 assets, address receiver, address borrower) external returns (uint256 borrowShares);
    function repay(uint256 assets, address borrower) external returns (uint256 actualRepay, uint256 borrowShares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function accountSnapshot(address account) external view returns (uint256 supply, uint256 borrow);
    function auditor() external view returns (address);
}