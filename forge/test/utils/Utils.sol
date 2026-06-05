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

    function bytesToStr(bytes4 buffer) public pure returns (string memory) {
        return bytesToStr(abi.encode(buffer));
    }

    function addrToStr(address a) public pure returns (string memory) {
        return bytesToStr(abi.encodePacked(a));
    }

    function addrToStr(address[] memory a) public pure returns (string memory t) {
        if (a.length == 0) return "[]";
        if (a.length == 1) return string.concat("[", bytesToStr(abi.encodePacked(a[0])), "]");
        t = string.concat("[", bytesToStr(abi.encodePacked(a[0])));
        for (uint i = 1; i < a.length; i++) {
            t = string.concat(t, ",", bytesToStr(abi.encodePacked(a[i])));
        }
        t = string.concat(t, "]");
    }

    function print(address[] memory a) public pure {
        for (uint i; i < a.length; ++i) {
            console.log(i, a[i]);
        }
    }

    function print(address[11] memory a) public pure {
        for (uint i; i < a.length; ++i) {
            console.log(i, a[i]);
        }
    }
}