// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseStrategyTest.t.sol";
import "../../../contracts/BIFI/strategies/Common/BaseAllToNativeFactoryStrat.sol";

abstract contract BaseAllToNativeFactoryTest is BaseStrategyTest {

    function claimRewardsToStrat() internal virtual {
        BaseAllToNativeFactoryStrat(payable(vault.strategy())).claim();
    }

    function test_rewards() external {
        BaseAllToNativeFactoryStrat strategy = BaseAllToNativeFactoryStrat(payable(vault.strategy()));
        vm.prank(strategy.keeper());
        strategy.setHarvestOnDeposit(false);

        _depositIntoVault(user, wantAmount);
        skip(delay);

        claimRewardsToStrat();
        beforeHarvest();

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
        address native = strategy.native();
        uint nativeBal = IERC20(native).balanceOf(address(strategy));
        console.log("WETH %18e", nativeBal);

        (, bytes memory data0) = address(strategy).call(abi.encodeWithSignature("lpToken0()"));
        (, bytes memory data1) = address(strategy).call(abi.encodeWithSignature("lpToken1()"));
        address lp0; address lp1;
        if (data0.length > 0) {
            lp0 = abi.decode(data0, (address));
            uint bal = IERC20(lp0).balanceOf(address(strategy));
            console.log("lpToken0 %18e", bal);
        }
        if (data1.length > 0) {
            lp1 = abi.decode(data1, (address));
            uint bal = IERC20(lp1).balanceOf(address(strategy));
            console.log("lpToken1 %18e", bal);
        }
        if (lp0 != native && lp1 != native) {
            assertEq(nativeBal, 0, "Native not swapped");
        }
    }

    receive() external payable {}
}