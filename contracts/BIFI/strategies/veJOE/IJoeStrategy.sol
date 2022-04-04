// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

pragma solidity ^0.8.0;

interface IJoeStrategy {
    function want() external view returns (IERC20Upgradeable);
    function pid() external view returns (uint256);
}