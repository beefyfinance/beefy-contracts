// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface INutsStaking {
    function balances(address account) external view returns (uint256);
    function depositFor(address player, uint256 amount) external;
    function cashout(uint256 amount) external;
    function claimYield() external;
}