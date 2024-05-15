// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Pendle/StrategyEquilibria.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyEquilibriaTest is BaseStrategyTest {

    StrategyEquilibria strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyEquilibria();
        else strategy = StrategyEquilibria(payable(_impl));
        return address(strategy);
    }

    function test_rewards() external {
        _depositIntoVault(user, wantAmount);
        skip(1 days);

        strategy.rewardPool().getReward(address(strategy));

        for (uint i; i < strategy.rewardsLength(); ++i) {
            uint bal = IERC20(strategy.rewards(i)).balanceOf(address(strategy));
            console.log(IERC20Extended(strategy.rewards(i)).symbol(), bal);
        }

        console.log("Harvest");
        strategy.harvest();

        for (uint i; i < strategy.rewardsLength(); ++i) {
            uint bal = IERC20(strategy.rewards(i)).balanceOf(address(strategy));
            console.log(IERC20Extended(strategy.rewards(i)).symbol(), bal);
        }
    }

    function test_redeem() public {
        _depositIntoVault(user, wantAmount);
        skip(1 days);

        uint minRedeemDuration = strategy.xEqb().minRedeemDuration();
        vm.prank(strategy.keeper());
        strategy.setRedeemEqb(true, 1 days);

        strategy.harvest();
        uint redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 1, "Not 1 redeem after first harvest");
        (,,uint256 endTime) = strategy.xEqb().getUserRedeem(address(strategy), 0);

        skip(12 hours);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 1, "Should be still 1 redeem before delay");

        skip(13 hours);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 2, "Not 2 redeems after redeem delay");

        skip(minRedeemDuration);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 2, "Not 2 redeems after 1st redeem duration");
        (,, uint256 endTimeNext) = strategy.xEqb().getUserRedeem(address(strategy), 0);
        assertGt(endTimeNext, endTime, "1st redeem not updated");

        // disable redeems
        vm.prank(strategy.keeper());
        strategy.setRedeemEqb(false, 0);
        skip(25 hours);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 2, "Redeems updated when 'redeemEqb' is false");

        // enable redeems but increase delay to not create new redeems
        vm.prank(strategy.keeper());
        strategy.setRedeemEqb(true, minRedeemDuration + 1 weeks);
        skip(minRedeemDuration);
        deal(address(strategy.xEqb()), address(strategy), 10e18);
        strategy.harvest();
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 1, "Not redeemed after re-enable");
        uint xEqbBal = strategy.xEqb().balanceOf(address(strategy));
        assertGt(xEqbBal, 0, "Should not redeem xEqb");
    }

    function test_manualRedeem() public {
        uint minRedeemDuration = strategy.xEqb().minRedeemDuration();
        vm.prank(strategy.keeper());
        strategy.setRedeemEqb(false, 0);

        _depositIntoVault(user, wantAmount);
        skip(1 days);
        strategy.harvest();

        // redeem manually
        vm.prank(strategy.keeper());
        strategy.redeemAll();
        uint redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 1, "Not redeemed manually");
        uint xEqbBal = strategy.xEqb().balanceOf(address(strategy));
        assertEq(xEqbBal, 0, "Not all xEqb redeemed");

        // finalize manually
        IERC20 eqb = IERC20(strategy.booster().eqb());
        uint eqbBal = eqb.balanceOf(address(strategy));
        skip(minRedeemDuration + 1);
        vm.prank(strategy.keeper());
        strategy.finalizeRedeem(0);
        redeemLen = strategy.xEqb().getUserRedeemsLength(address(strategy));
        assertEq(redeemLen, 0, "Not finalized manually");
        assertGt(eqb.balanceOf(address(strategy)), eqbBal, "EQB not finalized");
    }

}