// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBankController {
    function getFTokeAddress(address underlying)
        external
        view
        returns (address);
}