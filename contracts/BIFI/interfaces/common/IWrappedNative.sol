// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IWrappedNative {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}
