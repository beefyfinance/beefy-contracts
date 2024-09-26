// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyFxConvex.sol";
import {BaseAllToNativeFactoryTest} from "./BaseAllToNativeFactoryTest.t.sol";

contract StrategyFxConvexTest is BaseAllToNativeFactoryTest {

    StrategyFxConvex strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyFxConvex();
        else strategy = StrategyFxConvex(payable(_impl));
        return address(strategy);
    }

    function claimRewardsToStrat() internal override {
        IConvexVault(strategy.cvxVault()).getReward(true);
    }
}