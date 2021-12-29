// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

library UpkeepHelper {
    uint256 public constant BASE_PREMIUM = 10 ** 8;

    // function used to iterate on an array in a circular way
    function _getCircularIndex(uint256 index, uint256 offset, uint256 bufferLength) internal pure returns (uint256) {
        return (index + offset) % bufferLength;
    }

    
}