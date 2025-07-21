// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVoterOpx {
    function vote(uint256 tokenId, uint256[] calldata weights) external;
    function reset(uint256 tokenId) external;
}