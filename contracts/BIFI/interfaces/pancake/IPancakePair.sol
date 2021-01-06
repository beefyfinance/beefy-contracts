// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IPancakePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}
