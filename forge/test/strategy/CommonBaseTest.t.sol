// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeFactoryTest.t.sol";
import {StrategyConvexStakingFraxtal} from "../../../contracts/BIFI/strategies/Curve/StrategyConvexStakingFraxtal.sol";
import {StrategyMimSwap} from "../../../contracts/BIFI/strategies/degens/StrategyMimSwap.sol";
import {StrategyPearlV1} from "../../../contracts/BIFI/strategies/degens/StrategyPearlV1.sol";
import {StrategyConvexCVX} from "../../../contracts/BIFI/strategies/Curve/StrategyConvexCVX.sol";
import {StrategyCommonSingleStakingFactory} from "../../../contracts/BIFI/strategies/Common/StrategyCommonSingleStakingFactory.sol";

contract CommonBaseTest is BaseAllToNativeFactoryTest {

    address private strategy;

    function createStrategy(address _impl) internal override returns (address) {
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

    function claimRewardsToStrat() internal override {
        BaseAllToNativeFactoryStrat(payable(strategy)).claim();
    }
}