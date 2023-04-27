// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

interface ICrvMinter {
    function mint(address _gauge) external;
}