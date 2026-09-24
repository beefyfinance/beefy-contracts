// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBaseSwapVesting {
    function redeem(uint256 xTokenAmount, uint256 duration) external;
    function finalizeRedeem(uint256 redeemIndex) external;
    function getUserRedeemsLength(address userAddress) external view returns (uint256);
    function getUserRedeem(address userAddress, uint256 redeemIndex) external view returns (
        uint256 amount,
        uint256 xTokenAmount,
        uint256 endTime,
        address dividendsContract,
        uint256 dividendsAllocation
    );
}