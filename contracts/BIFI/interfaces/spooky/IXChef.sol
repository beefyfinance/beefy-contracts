// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

interface IXChef {
    function deposit(uint256 pid, uint256 amount) external;
    function withdraw(uint256 pid, uint256 amount) external;
    function userInfo(uint256 pid, address user) external view returns (uint256, uint256);
    function poolInfo(uint256 pid) external view returns (
        address RewardToken,
        uint256 RewardPerSecond,
        uint256 TokenPrecision,
        uint256 xBooStakedAmount,
        uint256 lastRewardTime,
        uint256 accRewardPerShare,
        uint256 endTime,
        uint256 startTime,
        uint256 userLimitEndTime,
        address protocolOwnerAddress
    );
    function pendingReward(uint256 pid, address user) external view returns (uint256);
    function emergencyWithdraw(uint256 pid) external;
}