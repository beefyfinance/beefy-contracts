// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

library StringUtils {
    function concat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
}