// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IWBNB is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}