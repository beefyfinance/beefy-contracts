// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAaveV4Hub {
    function previewAddByAssets(uint256 assetId, uint256 assets) external view returns (uint256);
    function previewRemoveByShares(uint256 assetId, uint256 shares) external view returns (uint256);
}

interface IAaveV4Spoke {
    struct Reserve {
        address underlying;
        IAaveV4Hub hub;
        uint16 assetId;
        uint8 decimals;
        uint24 collateralRisk;
        uint8 flags;
        uint32 dynamicConfigKey;
    }

    function getReserve(uint256 reserveId) external view returns (Reserve memory);
    function getUserSuppliedAssets(uint256 reserveId, address user) external view returns (uint256);
    function getUserSuppliedShares(uint256 reserveId, address user) external view returns (uint256);
    function supply(uint256 reserveId, uint256 amount, address onBehalfOf)
        external
        returns (uint256 shares, uint256 assets);
    function withdraw(uint256 reserveId, uint256 amount, address onBehalfOf)
        external
        returns (uint256 shares, uint256 assets);
}
