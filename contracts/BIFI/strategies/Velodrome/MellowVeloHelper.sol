// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IMellow.sol";
import "../../interfaces/common/ISolidlyGauge.sol";

contract MellowVeloHelper {

    function rewardRate(address[] calldata lps) public view returns (uint[] memory) {
        uint[] memory rates = new uint[](lps.length);
        for (uint j = 0; j < lps.length; j++) {
            IMellowLpWrapper lp = IMellowLpWrapper(lps[j]);
            IMellowCore core = IMellowCore(lp.core());
            IMellowCore.ManagedPositionInfo memory pos = core.managedPositionAt(lp.positionId());
            ISolidlyGauge gauge = ISolidlyGauge(ICLPool(lp.pool()).gauge());

            uint rate;
            for (uint i = 0; i < pos.ammPositionIds.length; i++) {
                uint tokenId = pos.ammPositionIds[i];
                uint earned = gauge.earned(address(core), tokenId);
                uint prevTime = gauge.lastUpdateTime(tokenId);
                rate += earned / (block.timestamp - prevTime);
            }
            rates[j] = rate;
        }
        return rates;
    }

//    function rewardRate(IMellowLpWrapper lp) public returns (uint rate) {
//        // trigger new rewards
//        lp.collectRewards();
//
//        uint lastTime = block.timestamp;
//        uint lastIndex = lp.timestampToRewardRatesIndex(lastTime);
//        (, uint lastRate) = lp.rewardRates(lastIndex);
//        (uint prevTime, uint prevRate) = lp.rewardRates(lastIndex - 1);
//        rate = (lastRate - prevRate) * lp.totalSupply() / (2 ** 96) / (lastTime - prevTime);
//    }
}