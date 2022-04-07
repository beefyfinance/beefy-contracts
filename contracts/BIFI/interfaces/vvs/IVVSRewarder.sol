// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IVVSRewarder {
    function pendingToken(uint256 _pid, address _user) external view returns (address token, uint256 amount);
} 