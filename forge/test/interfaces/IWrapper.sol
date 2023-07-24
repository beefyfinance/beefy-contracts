// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0 <0.9.0;

interface IWrapper {
    function wrapAll() external;
    function wrap(uint256 amount) external;
    function unwrapAll() external;
    function unwrap(uint256 amount) external;
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256);
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256);
    function totalAssets() external returns (uint256);
    function totalSupply() external returns (uint256);
    function asset() external view returns (address);
    function balanceOf(address user) external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
}