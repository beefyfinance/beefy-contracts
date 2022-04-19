// SPDX-License-Identifier: MIT

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

pragma solidity ^0.8.0;

interface ICakeBoostStrategy {
    function want() external view returns (IERC20);
    function poolId() external view returns (uint256);
    function chef() external view returns (address);
}