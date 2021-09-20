// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./IGasPrice.sol";

contract GasThrottlerArb {

    address public gasprice = address(0);
    address public keeper;

    /**
     * @param _keeper address that manages gas throttler.
     */
    constructor(
        address _keeper
    ) public {
        keeper = _keeper;
    }

    modifier gasThrottle(bool shouldCheckGasPrice) {
        require(shouldCheckGasPrice && gasprice != address(0) && tx.gasprice <= IGasPrice(gasprice).maxGasPrice(), "gas is too high!");
        _;
    }

    // checks that caller is keeper.
    modifier onlyKeeper() {
        require(msg.sender == keeper, "!keeper");
        _;
    }

    /**
     * @dev Updates address of the keeper.
     * @param _keeper new keeper address.
     */
    function setKeeper(address _keeper) external onlyKeeper {
        keeper = _keeper;
    }

    function setGasprice(address _gasprice) external onlyKeeper {
        gasprice = _gasprice;
    }
}