// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";

interface ICommonRewarderV8 {
    function pendingTokens(uint256 _pid, address _user, uint256 _rewardAmount) external view returns (IERC20[] memory tokens, uint256[] memory amounts);
} 