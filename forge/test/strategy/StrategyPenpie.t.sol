// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeFactoryTest.t.sol";
import "../../../contracts/BIFI/strategies/Pendle/StrategyPenpie.sol";

contract StrategyPenpieTest is BaseAllToNativeFactoryTest {

    StrategyPenpie strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyPenpie();
        else strategy = StrategyPenpie(payable(_impl));
//        deal(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8, address(strategy), 1000e18);
//        deal(0x912CE59144191C1204E64559FE8253a0e49E6548, address(strategy), 1000e18);
        return address(strategy);
    }

    function beforeHarvest() internal override {
        vm.roll(block.number + 7200); // skip ~24h to accrue pendle rewards
    }

    function claimRewardsToStrat() internal override {
        vm.roll(block.number + 7200); // skip ~24h to accrue pendle rewards

        strategy.pendleStaking().harvestMarketReward(strategy.want(), address(this), 0);
        address[] memory lps = new address[](1);
        address[][] memory tokens = new address[][](1);
        lps[0] = strategy.want();
        strategy.masterPenpie().multiclaimFor(lps, tokens, address(strategy));
    }
}