// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStratX {
    function sharesTotal() external view returns(uint256);
    function farm() external;
}