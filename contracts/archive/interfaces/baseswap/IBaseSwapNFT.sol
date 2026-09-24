// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBaseSwapNFT {
    function createPosition(uint256 amount, uint256 lockDuration) external;
    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;
    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;
    function emergencyWithdraw(uint256 tokenId) external;
    function harvestPosition(uint256 tokenId) external;
    function getStakingPosition(uint256 tokenId) external view returns (
        uint256 amount,
        uint256 amountWithMultiplier,
        uint256 startLockTime,
        uint256 lockDuration,
        uint256 lockMultiplier,
        uint256 rewardDebt,
        uint256 rewardDebtWETH,
        uint256 boostPoints,
        uint256 totalMultiplier
    );
    function pendingRewards(uint256 tokenId) external view returns (
        uint256 mainAmount,
        uint256 wethAmount
    );
    function getPoolInfo() external view returns (
        address lpToken,
        address protocolToken,
        address xToken,
        uint256 lastRewardTime,
        uint256 accRewardsPerShare,
        uint256 accRewardsPerShareWETH,
        uint256 lpSupply,
        uint256 lpSupplyWithMultiplier,
        uint256 allocPoints,
        uint256 allocPointsWETH
    );
    function lastTokenId() external view returns (uint256);
    function exists(uint256 tokenId) external view returns (bool);
}