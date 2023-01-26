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
import "../../../contracts/BIFI/strategies/Curve/StrategyConvexCRV.sol";

contract StrategyProdCvxCrv is Test {

    uint256 wantAmount = 5000000 ether;

    IVault vault;
    StrategyConvexCRV strategy;
    VaultUser user;

    function setUp() public {
        address _vault = vm.envAddress("VAULT");
        console.log("Testing vault at", _vault);
        vault = IVault(_vault);
        console.log(vault.name(), vault.symbol());
        strategy = StrategyConvexCRV(payable(vault.strategy()));
        user = new VaultUser();
        deal(vault.want(), address(user), wantAmount);
    }

    function test_prodHarvest() external {
        user.approve(vault.want(), address(vault), wantAmount);
        user.depositAll(vault);

        uint vaultBalance = vault.balance();
        uint pps = vault.getPricePerFullShare();
        uint lastHarvest = strategy.lastHarvest();

        vm.prank(strategy.keeper());
        strategy.setRewardWeight(0);
        skip(1 days);

        address[] memory rewards = new address[](strategy.rewardsLength() + strategy.rewardsV3Length());
        for(uint i; i < strategy.rewardsLength(); ++i) {
            rewards[i] = strategy.rewardToNative(i)[0];
        }
        for(uint i; i < strategy.rewardsV3Length(); ++i) {
            rewards[strategy.rewardsLength() + i] = strategy.rewardV3ToNative(i)[0];
        }

        console.log("Claim rewards on Convex");
        strategy.stakedCvxCrv().getReward(address(strategy));
        uint crvBal = IERC20(strategy.crv()).balanceOf(address(strategy));
        uint cvxBal = IERC20(strategy.cvx()).balanceOf(address(strategy));
        uint nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        console.log("CRV", crvBal);
        console.log("CVX", cvxBal);
        for (uint i; i < rewards.length; ++i) {
            string memory s = IERC20Extended(rewards[i]).symbol();
            console2.log(s, IERC20(rewards[i]).balanceOf(address(strategy)));
        }
        console.log("WETH", nativeBal);
        deal(strategy.crv(), address(strategy), 1e20);
        deal(strategy.cvx(), address(strategy), 1e20);

        console.log("Harvesting vault");
        strategy.harvest();
        crvBal = IERC20(strategy.crv()).balanceOf(address(strategy));
        cvxBal = IERC20(strategy.cvx()).balanceOf(address(strategy));
        nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        console.log("CRV", crvBal);
        console.log("CVX", cvxBal);
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i]).balanceOf(address(strategy));
            string memory s = IERC20Extended(rewards[i]).symbol();
            console2.log(s, bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
        console.log("WETH", nativeBal);
        assertEq(crvBal, 0, "CRV not swapped");
        assertEq(crvBal, 0, "CVX not swapped");
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