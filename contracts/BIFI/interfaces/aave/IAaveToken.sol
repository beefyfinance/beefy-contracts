// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IAaveToken {
    function POOL() external view returns (address);
    function getIncentivesController() external view returns (address);
}
