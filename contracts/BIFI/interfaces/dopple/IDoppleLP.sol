// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IDoppleLP {
    function swap() external view returns (address);
}