// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IStratX {
    function sharesTotal() external view returns(uint256);
    function farm() external;
}