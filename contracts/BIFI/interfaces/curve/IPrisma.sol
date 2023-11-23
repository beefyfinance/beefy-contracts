// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPrismaRewardPool {
    function balanceOf(address a) external view returns (uint256);
    function deposit(address receiver, uint256 amount) external returns (bool);
    function withdraw(address receiver, uint256 amount) external returns (bool);
    function claimableReward(address account) external view returns (uint256 prismaAmount);
}

interface IPrismaVault {
    function batchClaimRewards(
        address receiver,
        address boostDelegate,
        address[] calldata rewardContracts,
        uint256 maxFeePct
    ) external returns (bool);

    // Get the remaining claimable amounts this week that will receive boost
    function getClaimableWithBoost(address claimant) external view returns (uint256 maxBoosted, uint256 boosted);
}