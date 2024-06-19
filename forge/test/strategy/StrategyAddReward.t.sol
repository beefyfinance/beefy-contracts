// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "./BaseAllToNativeFactoryTest.t.sol";
import "../../../contracts/BIFI/interfaces/curve/IRewardsGauge.sol";

contract StrategyAddRewardTest is BaseAllToNativeFactoryTest {

    IStrategy strategy;

    function createStrategy(address) internal override returns (address) {
        strategy = IStrategy(vm.envAddress("STRAT"));
        IVault vault = IVault(strategy.vault());
        console.log(vault.name(), vault.symbol());

        address reward = vm.envAddress("REWARD");
        vm.prank(strategy.keeper());
        BaseAllToNativeFactoryStrat(payable(address(strategy))).addReward(reward);

        return address(strategy);
    }

    function claimRewardsToStrat() internal override {
        (bool success, bytes memory res) = address(strategy).staticcall(abi.encodeWithSignature("gauge()"));
        if (success) {
            address gauge = abi.decode(res, (address));
            IRewardsGauge(gauge).claim_rewards(address(strategy));
        }
    }
}