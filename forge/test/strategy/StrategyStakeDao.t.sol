// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeFactoryTest.t.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyStakeDao.sol";

contract StrategyStakeDaoTest is BaseAllToNativeFactoryTest {

    StrategyStakeDao strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyStakeDao();
        else strategy = StrategyStakeDao(payable(_impl));
        return address(strategy);
    }

    function claimRewardsToStrat() internal override {
        IRewardsGauge(strategy.sdGauge()).claim_rewards(address(strategy));
    }
}