// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface INutsLPStaking {
    function balances(address account) external view returns (uint256);
    function deposit(uint256 amount) external;
    function cashout(uint256 amount) external;
    function claimYield() external;
}