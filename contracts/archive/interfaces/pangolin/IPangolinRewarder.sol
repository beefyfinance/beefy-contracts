// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPangolinRewarder {
    function pendingTokens(uint256 _pid, address _user, uint256 _rewardAmount) external view returns (IERC20[] memory tokens, uint256[] memory amounts);
} 