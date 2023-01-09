// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IBeefyVaultV7Multi {
    struct StrategyParams {
        uint256 activation;
        uint256 allocBPS;
        uint256 allocated;
        uint256 gains;
        uint256 losses;
        uint256 lastReport;
    }
    function convertToAssets(uint256 shares) external view returns (uint256);
    function strategies(address strategy) external view returns (StrategyParams memory);
    function availableCapital(address strategy) external view returns (int256);
    function report(int256 roi, uint256 repayment) external returns (uint256);
    function revokeStrategy() external;
}
