// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../node_modules/forge-std/src/Test.sol";

library Utils {
    function bytesToStr(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);
        bytes memory _base = "0123456789abcdef";
        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }
        return string(abi.encodePacked("0x", converted));
    }

    function print(address[] memory a) public view {
        for (uint i; i < a.length; ++i) {
            console.log(i, a[i]);
        }
    }

    function print(address[11] memory a) public view {
        for (uint i; i < a.length; ++i) {
            console.log(i, a[i]);
        }
    }
}