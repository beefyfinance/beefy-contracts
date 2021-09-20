// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IGasPrice.sol";

contract GasThrottlerArb is Ownable {

    address public gasprice = address(0);

    modifier gasThrottle() {
        require(gasprice != address(0) && tx.gasprice <= IGasPrice(gasprice).maxGasPrice(), "gas is too high!");
        _;
    }

    function setGasprice(address _gasprice) external onlyOwner {
        gasprice = _gasprice;
    }
}