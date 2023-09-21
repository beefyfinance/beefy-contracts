// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IRewardsLocker {
    function numVestingSchedules(
        address account,
        IERC20 token
    ) external view returns (uint256);
    function vestSchedulesInRange(
        IERC20 token,
        uint256 startIndex,
        uint256 endIndex
    ) external returns (uint256);
}