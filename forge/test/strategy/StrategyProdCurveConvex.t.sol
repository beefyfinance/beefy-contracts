// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "forge-std/Test.sol";
import "../../../node_modules/forge-std/src/Test.sol";

// Users
import "../users/VaultUser.sol";
// Interfaces
import "../interfaces/IVault.sol";
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvex.sol";

contract StrategyProdCurveConvex is Test {

    uint256 wantAmount = 5000000 ether;

    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    IVault vault;
    StrategyCurveConvex strategy;
    VaultUser user;

    function setUp() public {
        address _vault = vm.envAddress("VAULT");
        console.log("Testing vault at", _vault);
        vault = IVault(_vault);
        console.log(vault.name(), vault.symbol());
        strategy = StrategyCurveConvex(payable(vault.strategy()));
        user = new VaultUser();
        deal(vault.want(), address(user), wantAmount);
    }

    function test_prodHarvest() external {
        user.approve(vault.want(), address(vault), wantAmount);
        user.depositAll(vault);

        uint vaultBalance = vault.balance();
        uint pps = vault.getPricePerFullShare();
        uint lastHarvest = strategy.lastHarvest();

        if (strategy.rewardPool() != address(0)) {
            strategy.booster().earmarkRewards(strategy.pid());
        }

        skip(1 days);

        if (strategy.rewardPool() != address(0)) {
            uint rewardsAvailable = strategy.rewardsAvailable();
            assertGt(rewardsAvailable, 0, "Expected rewardsAvailable > 0");
        }

        address[] memory rewards = new address[](strategy.rewardsV2Length() + strategy.rewardsV3Length());
        for(uint i; i < strategy.rewardsV2Length(); ++i) {
            (,address[] memory route,) = strategy.rewardV2(i);
            rewards[i] = route[0];
        }
        for(uint i; i < strategy.rewardsV3Length(); ++i) {
            rewards[strategy.rewardsV2Length() + i] = strategy.rewardV3Route(i)[0];
        }

        if (strategy.rewardPool() != address(0)) {
            console.log("Claim rewards on Convex");
            IConvexRewardPool(strategy.rewardPool()).getReward(address(strategy), true);
        } else {
            IRewardsGauge(strategy.gauge()).claim_rewards(address(strategy));
        }
        uint nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        for (uint i; i < rewards.length; ++i) {
            string memory s = IERC20Extended(rewards[i]).symbol();
            console2.log(s, IERC20(rewards[i]).balanceOf(address(strategy)));
        }
        console.log("WETH", nativeBal);

        console.log("Harvesting vault");
        strategy.harvest();
        nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i]).balanceOf(address(strategy));
            string memory s = IERC20Extended(rewards[i]).symbol();
            console2.log(s, bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
        console.log("WETH", nativeBal);
        assertEq(nativeBal, 0, "Native not swapped");

        uint256 vaultBalAfterHarvest = vault.balance();
        uint256 ppsAfterHarvest = vault.getPricePerFullShare();
        uint256 lastHarvestAfterHarvest = strategy.lastHarvest();
        console.log("Balance", vaultBalance, vaultBalAfterHarvest);
        console.log("PPS", pps, ppsAfterHarvest);
        console.log("LastHarvest", lastHarvest, lastHarvestAfterHarvest);
        assertGt(vaultBalAfterHarvest, vaultBalance, "Harvested 0");
        assertGt(ppsAfterHarvest, pps, "Expected ppsAfterHarvest > initial");
        assertGt(lastHarvestAfterHarvest, lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");

        console.log("Panic");
        vm.prank(strategy.keeper());
        strategy.panic();

        console.log("Unpause");
        vm.prank(strategy.keeper());
        strategy.unpause();

        console.log("Withdrawal");
        user.withdrawAll(vault);
        uint userBal = IERC20(vault.want()).balanceOf(address(user));
        console.log("User balance after withdrawal", userBal);
        assertGt(userBal, wantAmount * 99 / 100, "Expected balance increase");
    }
}