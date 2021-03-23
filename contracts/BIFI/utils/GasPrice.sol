// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

contract GasPrice is Ownable {

    uint public maxGasPrice = 10000000000; // 10 gwei

    event NewMaxGasPrice(uint oldPrice, uint newPrice);

    function setMaxGasPrice(uint _maxGasPrice) external onlyOwner {
        emit NewMaxGasPrice(maxGasPrice, _maxGasPrice);
        maxGasPrice = _maxGasPrice;
    }
}