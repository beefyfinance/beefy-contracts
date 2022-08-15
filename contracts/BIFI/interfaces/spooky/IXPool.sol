// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

interface IXPool {
    function enter(uint256 amount) external;
    function leave(uint256 amount) external;
    function xBOOForBOO(uint256 amount) external view returns (uint256);
    function BOOForxBOO(uint256 amount) external view returns (uint256);
}