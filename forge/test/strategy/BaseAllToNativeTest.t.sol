// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseStrategyTest.t.sol";
import "../../../contracts/BIFI/strategies/Common/BaseAllToNativeStrat.sol";

abstract contract BaseAllToNativeTest is BaseStrategyTest {

    function claimRewardsToStrat() internal virtual {}

    function test_rewards() external {
        BaseAllToNativeStrat strategy = BaseAllToNativeStrat(vault.strategy());

        _depositIntoVault(user, wantAmount);
        skip(1 days);

        claimRewardsToStrat();

        for (uint i; i < strategy.rewardsLength(); ++i) {
            uint bal = IERC20(strategy.rewards(i)).balanceOf(address(strategy));
            console.log(IERC20Extended(strategy.rewards(i)).symbol(), bal);
        }

        console.log("Harvest");
        strategy.harvest();

        for (uint i; i < strategy.rewardsLength(); ++i) {
            uint bal = IERC20(strategy.rewards(i)).balanceOf(address(strategy));
            console.log(IERC20Extended(strategy.rewards(i)).symbol(), bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
        uint nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        console.log("WETH", nativeBal);
        assertEq(nativeBal, 0, "Native not swapped");
    }

}