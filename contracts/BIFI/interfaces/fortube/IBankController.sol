// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IBankController {
    function getFTokeAddress(address underlying)
        external
        view
        returns (address);
}