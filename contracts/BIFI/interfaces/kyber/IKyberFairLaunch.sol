// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IKyberFairLaunch {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _shouldHarvest
    ) external;

    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function harvest(uint256 _pid) external;

    function getUserInfo(
        uint256 _pid,
        address _account
    ) external view returns (
        uint256 amount,
        uint256[] memory unclaimedRewards,
        uint256[] memory lastRewardPerShares
    );

    function pendingRewards(
        uint256 _pid,
        address _user
    ) external view returns (
        uint256[] memory rewards
    );
}