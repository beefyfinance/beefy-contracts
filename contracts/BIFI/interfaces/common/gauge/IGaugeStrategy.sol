// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

interface IGaugeStrategy {
    function want() external view returns (IERC20Upgradeable);
    function gauge() external view returns (address);
}
