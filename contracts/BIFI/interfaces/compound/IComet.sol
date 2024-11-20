// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IComet {
    function supply(address asset, uint amount) external;
    function withdraw(address asset, uint amount) external;
    function baseToken() external view returns (address);
}
