// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/degens/StrategyApeStaking.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyApeStakingTest is BaseStrategyTest {

    StrategyApeStaking strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyApeStaking();
        else strategy = StrategyApeStaking(_impl);
        return address(strategy);
    }
}