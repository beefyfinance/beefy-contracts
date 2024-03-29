// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeTest.t.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyFxConvex.sol";

contract StrategyFxConvexTest is BaseAllToNativeTest {

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