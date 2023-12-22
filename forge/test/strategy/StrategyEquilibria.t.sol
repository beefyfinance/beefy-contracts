// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "forge-std/Test.sol";
import "../../../node_modules/forge-std/src/Test.sol";

// Users
import "../users/VaultUser.sol";
// Interfaces
import "./BaseStrategyTest.t.sol";
import "../interfaces/IERC20Like.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/infra/SimpleSwapper.sol";
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/strategies/Pendle/StrategyEquilibria.sol";

contract StrategyEquilibriaTest is BaseStrategyTest {

    IVault vault;
    VaultUser user = new VaultUser();
    uint256 wantAmount = 500000 ether;
    StrategyEquilibria strategy = new StrategyEquilibria();

    function setUp() public {
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyEquilibria(payable(vault.strategy()));
            console.log("Testing vault at", vaultAddress);
            console.log(vault.name(), vault.symbol());
        } else {
            BeefyVaultV7 vaultV7 = new BeefyVaultV7();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            vault = IVault(address(vaultV7));

            bytes memory initData = vm.envBytes("INIT_DATA");
            (bool success,) = address(strategy).call(initData);
            assertTrue(success, "Strategy initialize not success");

            strategy.setVault(address(vault));
            assertEq(strategy.vault(), address(vault), "Vault not set");
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
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