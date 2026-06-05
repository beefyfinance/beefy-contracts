// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDystVoter {
    function vote(uint tokenId, address[] calldata _poolVote, int256[] calldata _weights) external;
    function whitelist(address token, uint256 tokenId) external;
    function gauges(address lp) external view returns (address);
    function ve() external view returns (address);
    function minter() external view returns (address);
    function reset(uint256 _id) external;
    function bribes(address _lp) external view returns (address);
    function internal_bribes(address _lp) external view returns (address);
}