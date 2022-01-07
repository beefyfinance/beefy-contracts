// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IMasonry {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function exit() external;
    function claimReward() external;
    function earned(address mason) external view returns (uint256);
    function epoch() external view returns (uint256);
    function nextEpochPoint() external view returns (uint256);
    function canClaimReward(address mason) external view returns (bool);
    function canWithdraw(address mason) external view returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function masons(address mason) external view returns (uint256, uint256, uint256);
}
