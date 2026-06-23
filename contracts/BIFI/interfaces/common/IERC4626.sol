// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC4626 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /// @notice Address of the underlying asset
    function asset() external view returns (address assetTokenAddress);

    /// @notice Total underlying assets managed by the vault
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /// @notice Converts assets to shares
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /// @notice Converts shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /// @notice Maximum assets that can be deposited for receiver
    function maxDeposit(address receiver) external view returns (uint256 maxAssets);

    /// @notice Preview shares minted from a deposit
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /// @notice Deposit assets and mint shares
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Maximum shares that can be minted for receiver
    function maxMint(address receiver) external view returns (uint256 maxShares);

    /// @notice Preview assets required to mint shares
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /// @notice Mint shares to receiver
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Maximum assets owner can withdraw
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    /// @notice Preview shares burned for a withdrawal
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /// @notice Withdraw assets to receiver
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    /// @notice Maximum shares owner can redeem
    function maxRedeem(address owner) external view returns (uint256 maxShares);

    /// @notice Preview assets received from redemption
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /// @notice Redeem shares for assets
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);
    
    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
}