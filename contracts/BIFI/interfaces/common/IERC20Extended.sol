// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IERC20Extended {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint);
}