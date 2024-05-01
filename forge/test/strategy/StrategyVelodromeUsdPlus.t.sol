// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Velodrome/StrategyVelodromeUsdPlus.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyVelodromeUsdPlusTest is BaseStrategyTest {

    StrategyVelodromeUsdPlus strategy;

    function createStrategy(address _impl) internal override returns (address) {
        wantAmount = 50 ether;
        if (_impl == a0) strategy = new StrategyVelodromeUsdPlus();
        else strategy = StrategyVelodromeUsdPlus(_impl);
        return address(strategy);
    }

    function test_setOutputToUsdcRoute() public {
        ISolidlyRouter.Route[] memory badUsdcRoute = new ISolidlyRouter.Route[](1);
        badUsdcRoute[0] = ISolidlyRouter.Route(0x940181a94A35A4569E4529A3CDfB74e38FD98631, 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA, false, address(0));
        vm.prank(strategy.keeper());
        strategy.setOutputToUsdcRoute(badUsdcRoute);

        deal(address(want), address(user), wantAmount);
        _depositIntoVault(user, wantAmount);
        skip(1 days);
        console.log("Harvesting with wrong USDC reverts");
        vm.expectRevert("Only asset available for buy");
        strategy.harvest();

        ISolidlyRouter.Route[] memory goodUsdcRoute = new ISolidlyRouter.Route[](1);
        goodUsdcRoute[0] = ISolidlyRouter.Route(0x940181a94A35A4569E4529A3CDfB74e38FD98631, 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, false, address(0));
        vm.prank(strategy.keeper());
        strategy.setOutputToUsdcRoute(goodUsdcRoute);

        uint vaultBalance = vault.balance();
        uint pps = vault.getPricePerFullShare();
        uint lastHarvest = strategy.lastHarvest();

        console.log("Harvesting vault");
        strategy.harvest();

        skip(1 days);
        uint256 vaultBalAfterHarvest = vault.balance();
        uint256 ppsAfterHarvest = vault.getPricePerFullShare();
        uint256 lastHarvestAfterHarvest = strategy.lastHarvest();
        assertGt(vaultBalAfterHarvest, vaultBalance, "Harvested 0");
        assertGt(ppsAfterHarvest, pps, "Expected ppsAfterHarvest > initial");
        assertGt(lastHarvestAfterHarvest, lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");
    }
}