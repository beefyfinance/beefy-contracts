// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./IGasPrice.sol";

contract GasThrottlerArb {

    address public gasprice = address(0xA43509661141F254F54D9A326E8Ec851A0b95307);

    modifier gasThrottle(bool shouldGasThrottle) {
        require(shouldGasThrottle && tx.gasprice <= IGasPrice(gasprice).maxGasPrice(), "gas is too high!");
        _;
    }
}