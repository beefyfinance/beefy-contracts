// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INutsStaking {
    function balances(address account) external view returns (uint256);
    function depositFor(address player, uint256 amount) external;
    function cashout(uint256 amount) external;
    function claimYield() external;
}