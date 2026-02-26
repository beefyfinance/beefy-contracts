// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeFactoryTest.t.sol";

contract CommonBaseTest is BaseAllToNativeFactoryTest {

    address private strategy;

    function createStrategy(address _impl) internal override returns (address) {
        cacheOraclePrices();

        if (_impl != address(0)) {
            strategy = _impl;
            return strategy;
        }

        string memory stratCode = '';
        stratCode = vm.envOr("CODE", stratCode);
        require(bytes(stratCode).length > 0, "No CODE");

        bytes memory bytecode = vm.getCode(stratCode);
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        strategy = deployed;
        return strategy;
    }

    function beforeHarvest() internal virtual override {
//        deal(BaseAllToNativeFactoryStrat(payable(strategy)).rewards(0), address(strategy), 1000e18);
    }

    function cacheOraclePrices() internal {
        address redStoneBeraWETH = 0x3587a73AA02519335A8a6053a97657BECe0bC2Cc;
        if (redStoneBeraWETH.code.length > 0) {
            bytes memory _callData = abi.encodeWithSignature("latestAnswer()");
            (bool _success, bytes memory _res) = redStoneBeraWETH.staticcall(_callData);
            if (_success) {
                uint _price = abi.decode(_res, (uint));
                vm.mockCall(redStoneBeraWETH, _callData, abi.encode(_price));
            }
        }
    }
}