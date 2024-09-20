// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "./BaseAllToNativeFactoryTest.t.sol";
import "../../../contracts/BIFI/interfaces/common/IRewardPool.sol";
import {StrategyCurveConvex} from "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvex.sol";
import "../utils/Utils.sol";

contract StrategySetConvexPid is BaseAllToNativeFactoryTest {

    IStrategy strategy;
    uint pid;

    function createStrategy(address) internal override returns (address) {
        strategy = IStrategy(vm.envAddress("STRAT"));
        IVault vault = IVault(strategy.vault());
        console.log(vault.name(), vault.symbol());

        pid = vm.envUint("PID");
        vm.prank(strategy.owner());
        StrategyCurveConvex(address(strategy)).setConvexPid(pid);

        return address(strategy);
    }

    function claimRewardsToStrat() internal override {
        IRewardPool(StrategyCurveConvex(address(strategy)).rewardPool()).getReward(address(strategy));
    }


    function test_xprintCalls() public view {
        console.log("owner:", strategy.owner());

        console.log("\nCall:");
        console.log("target:", address(strategy));
        bytes memory data = abi.encodeCall(StrategyCurveConvex.setConvexPid, pid);
        console.log("data:", Utils.bytesToStr(data));
    }
}