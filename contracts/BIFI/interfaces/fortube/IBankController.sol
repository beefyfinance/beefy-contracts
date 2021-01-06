// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IBankController {
    function getFTokeAddress(address underlying)
        external
        view
        returns (address);
}