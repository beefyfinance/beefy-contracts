// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface ILendingPool {

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;

    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );

    function setUserEMode(uint8 categoryId) external;

    function getUserEMode(address user) external view returns (uint256);

    function getEModeCategoryData(uint8 categoryId) external view returns (
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationBonus,
        address priceSource,
        string memory label
    );
}