// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVeOpxRoom {
    function stake(uint256 tokenId) external;
    function claimReward() external;
    function exit() external;
    function emergencyWithdraw() external;
    function reward() external view returns (address);
}