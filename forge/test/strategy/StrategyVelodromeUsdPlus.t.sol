// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Velodrome/StrategyVelodromeUsdPlus.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyVelodromeUsdPlusTest is BaseStrategyTest {

    StrategyVelodromeUsdPlus strategy;

    function createStrategy(address _impl) internal override returns (address) {
        wantAmount = 50 ether;
        if (_impl == a0) strategy = new StrategyVelodromeUsdPlus();
        else strategy = StrategyVelodromeUsdPlus(_impl);
        return address(strategy);
    }
}