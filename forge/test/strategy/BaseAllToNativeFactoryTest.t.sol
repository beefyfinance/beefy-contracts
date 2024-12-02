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

        (bool success, bytes memory data) = address(strategy).call(abi.encodeWithSignature("lpToken0()"));
        if (success) {
            address lpToken = abi.decode(data, (address));
            uint bal = IERC20(lpToken).balanceOf(address(strategy));
            console.log("lpToken0", bal);
        }
        (success, data) = address(strategy).call(abi.encodeWithSignature("lpToken1()"));
        if (success) {
            address lpToken = abi.decode(data, (address));
            uint bal = IERC20(lpToken).balanceOf(address(strategy));
            console.log("lpToken1", bal);
        }
    }

    receive() external payable {}
}