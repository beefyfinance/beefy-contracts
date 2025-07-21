// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVeOpx {
    function opxNFT() external view returns (address);
    function voter() external view returns (address);
    function token() external view returns (address);
    function increase_amount(uint256 tokenId, uint256 value) external;
    function increase_unlock_time(uint256 tokenId, uint256 lock_duration) external;
    function locked(uint256 tokenId) external view returns (int128, uint256);
    function withdraw(uint256 tokenId) external;
    function create_lock(uint256 tokenId, uint256 value, uint256 lock_duration) external;
    function minLockedAmount() external view returns (uint256);
}