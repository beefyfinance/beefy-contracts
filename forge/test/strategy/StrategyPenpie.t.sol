// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeFactoryTest.t.sol";
import "../../../contracts/BIFI/strategies/Pendle/StrategyPenpie.sol";

contract StrategyPenpieTest is BaseAllToNativeFactoryTest {

    StrategyPenpie strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyPenpie();
        else strategy = StrategyPenpie(payable(_impl));
        return address(strategy);
    }

    function beforeHarvest() internal override {
        vm.roll(block.number + 1); // pass lastRewardBlock check in PendleMarket
        strategy.pendleStaking().harvestMarketReward(strategy.want(), address(this), 0);
        strategy.pendleStaking().harvestMarketReward(strategy.want(), address(this), 0);
    }

    function claimRewardsToStrat() internal override {
        vm.roll(block.number + 1); // pass lastRewardBlock check in PendleMarket
        strategy.pendleStaking().harvestMarketReward(strategy.want(), address(this), 0);
        strategy.pendleStaking().harvestMarketReward(strategy.want(), address(this), 0);

        strategy.claim();
    }
}