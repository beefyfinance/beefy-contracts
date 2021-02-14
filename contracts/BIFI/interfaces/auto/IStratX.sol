// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IStratX {
    function sharesTotal() external view returns(uint256);
    function farm() external;
}