// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract FixedOracle {

    function getPrice(bytes calldata data) external pure returns (uint256 price, bool success) {
        price = abi.decode(data, (uint));
        success = true;
    }

    function validateData(bytes calldata data) external view {}
}