// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "forge-std/Test.sol";
import "../../../node_modules/forge-std/src/Test.sol";

// Users
import "../users/VaultUser.sol";
// Interfaces
import "../interfaces/IERC20Like.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyPrisma.sol";
import "../utils/Utils.sol";

contract StrategyPrismaSetDepositRouteTest is Test {

    address native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address triUsdcPool = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address ngAdapter = 0xe09888EEab19bce85e67eDC59521F3f290B1BCcE;
    address mkUsdUsdcLp = 0xF980B4A4194694913Af231De69AB4593f5E0fCDc;
    address fraxBpPool = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2;
    address fraxBpLp = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC;
    address mkFraxBpLp = 0x0CFe5C777A7438C9Dd8Add53ed671cEc7A5FAeE5;

    StrategyPrisma strategy = StrategyPrisma(0x272516D919Bd88F2d64ab7075BBE9189b2Ebe1CB);
    address[11] route = [native, triUsdcPool, usdc, fraxBpPool, fraxBpLp, mkFraxBpLp, mkFraxBpLp];
    uint[5][5] params = [[2,0,1,2,3],[1,0,4,1,2],[1,0,4,1,2],[0,0,0,0,0]];

    function setUp() public view {
        console.log('route');
        Utils.print(route);
    }

    function test_setDepositToWant() external {
        vm.prank(strategy.keeper());
        strategy.setDepositToWant(route, params, 0);

        uint bal = strategy.balanceOf();
        uint lastHarvest = strategy.lastHarvest();

        strategy.harvest();
        // lockedProfit
        skip(1 days);

        uint256 balAfterHarvest = strategy.balanceOf();
        uint256 lastHarvestAfterHarvest = strategy.lastHarvest();
        assertGt(balAfterHarvest, bal, "Harvested 0");
        assertGt(lastHarvestAfterHarvest, lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");

        uint nativeBal = IERC20(native).balanceOf(address(strategy));
        assertEq(nativeBal, 0, "Native not swapped");
    }
}