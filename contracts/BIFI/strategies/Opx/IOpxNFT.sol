// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOpxNFT {
    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}