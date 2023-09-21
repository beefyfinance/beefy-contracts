// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IQuickDualRewards {
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerTokenA() external view returns (uint256);
    function rewardPerTokenB() external view returns (uint256);
    function earnedA(address account) external view returns (uint256);
    function earnedB(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
}
