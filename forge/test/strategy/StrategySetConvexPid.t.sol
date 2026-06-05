// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "./BaseAllToNativeFactoryTest.t.sol";
import "../../../contracts/BIFI/interfaces/common/IRewardPool.sol";
import {StrategyCurveConvexFactory} from "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvexFactory.sol";
import "../utils/Utils.sol";

contract StrategySetConvexPid is BaseAllToNativeFactoryTest {

    IStrategy strategy;
    StrategyCurveConvexFactory curveStrat;
    uint pid;

    function createStrategy(address) internal override returns (address) {
        strategy = IStrategy(vm.envAddress("STRAT"));
        IVault vault = IVault(strategy.vault());
        console.log(vault.name(), vault.symbol());

        pid = vm.envUint("PID");
        vm.prank(strategy.owner());

        curveStrat = StrategyCurveConvexFactory(payable(address(strategy)));
        curveStrat.setConvexPid(pid);

        return address(strategy);
    }

    function claimRewardsToStrat() internal override {
        IRewardPool(curveStrat.rewardPool()).getReward(address(strategy));
    }


    function test_xprintCalls() public view {
        console.log("owner:", strategy.owner());

        console.log("\nCall:");
        console.log("target:", address(strategy));
        bytes memory data = abi.encodeWithSignature("setConvexPid(uint256)", pid);
        console.log("data:", Utils.bytesToStr(data));
    }
}