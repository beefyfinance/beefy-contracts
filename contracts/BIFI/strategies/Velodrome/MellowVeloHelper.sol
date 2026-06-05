// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/common/ISolidlyGauge.sol";
import "./IMellow.sol";

contract MellowVeloHelper {

    ISolidlyGauge public reward = ISolidlyGauge(0x940181a94A35A4569E4529A3CDfB74e38FD98631);

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

    function rewardRateNew(address[] calldata lps) public returns (uint[] memory rates, uint[] memory periods) {
        rates = new uint[](lps.length);
        periods = new uint[](lps.length);
        for (uint j = 0; j < lps.length; j++) {
            IMellowLpWrapper lp = IMellowLpWrapper(lps[j]);

            uint before = reward.balanceOf(address(lp));
            lp.collectRewards();
            uint earned = reward.balanceOf(address(lp)) - before;

            uint lastIndex = lp.timestampToRewardRatesIndex(block.timestamp);
            (uint prevTime,) = lp.rewardRates(lastIndex - 1);
            periods[j] = block.timestamp - prevTime;

            rates[j] = earned / (block.timestamp - prevTime);
        }
    }
}