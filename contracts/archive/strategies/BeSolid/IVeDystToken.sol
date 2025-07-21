// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVeDystToken {
    function createLock(uint256 _value, uint256 _lockDuration) external returns (uint256 _tokenId);
    function increaseAmount(uint256 tokenId, uint256 value) external;
    function increaseUnlockTime(uint256 tokenId, uint256 duration) external;
    function withdraw(uint256 tokenId) external;
    function balanceOfNFT(uint256 tokenId) external view returns (uint256 balance);
    function locked(uint256 tokenId) external view returns (uint256 amount, uint256 endTime);
    function token() external view returns (address);
}