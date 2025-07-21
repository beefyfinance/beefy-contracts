// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeFactoryTest.t.sol";
import "../../../contracts/BIFI/strategies/Pendle/StrategyPenpie.sol";

contract StrategyPenpieTest is BaseAllToNativeFactoryTest {

    StrategyPenpie strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyPenpie();
        else strategy = StrategyPenpie(payable(_impl));
        cacheOraclePrices();
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

        // could be just "strategy.claim()" but arb impl doesn't have it
        address[] memory lps = new address[](1);
        address[][] memory tokens = new address[][](1);
        lps[0] = strategy.want();
        strategy.masterPenpie().multiclaimFor(lps, tokens, address(strategy));
    }

    function cacheOraclePrices() internal {
        address sBoldEthOracle = 0x91F98Acfd427401E661Bb300f61480349202Aaa0;
        if (sBoldEthOracle.code.length > 0) {
            address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            uint bal = IERC20(weth).balanceOf(0x50Bd66D59911F5e086Ec87aE43C811e0D059DD11);
            bytes memory callData = abi.encodeWithSignature("getQuote(uint256,address)", bal, weth);
            (, bytes memory resData) = sBoldEthOracle.staticcall(callData);
            vm.mockCall(sBoldEthOracle, callData, resData);
            callData = abi.encodeWithSignature("getQuote(uint256,address)", 1000000000000000000, 0x6440f144b7e50D6a8439336510312d2F54beB01D);
            (, resData) = sBoldEthOracle.staticcall(callData);
            vm.mockCall(sBoldEthOracle, callData, resData);
        }
        address lvlUSD = 0x9136aB0294986267b71BeED86A75eeb3336d09E1;
        if (lvlUSD.code.length > 0) {
            bytes memory data = abi.encodeWithSignature("setHeartBeat(address,uint256)", 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 100_000_000);
            vm.prank(OwnableUpgradeable(lvlUSD).owner());
            (bool success,) = lvlUSD.call(data);
            assertTrue(success, "lvlUSD setHeartBeat failed");
        }
        address midasDataFeed = 0x3aAc6fd73fA4e16Ec683BD4aaF5Ec89bb2C0EdC2;
        if (midasDataFeed.code.length > 0) {
            bytes memory data = abi.encodeWithSignature("setHealthyDiff(uint256)", 100_000_000);
            vm.prank(0xB60842E9DaBCd1C52e354ac30E82a97661cB7E89);
            (bool success,) = midasDataFeed.call(data);
            assertTrue(success, "midasDataFeed setHealthyDiff failed");
        }
    }
}