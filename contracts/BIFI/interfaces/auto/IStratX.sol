// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IStratX {
    function sharesTotal() external view returns(uint256);
    function farm() external;
}