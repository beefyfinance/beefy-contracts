// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IBankController {
    function getFTokeAddress(address underlying)
        external
        view
        returns (address);
}