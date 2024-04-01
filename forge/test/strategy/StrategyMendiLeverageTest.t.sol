// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "forge-std/Test.sol";
import "../../../node_modules/forge-std/src/Test.sol";

// Users
import "../users/VaultUser.sol";
// Interfaces
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/strategies/Mendi/StrategyMendiLeverage.sol";
import "../../../contracts/BIFI/interfaces/common/IVToken.sol";
import "../../../contracts/BIFI/interfaces/common/IComptroller.sol";

contract StrategyMendiLeverageTest is Test {

    uint256 wantAmount = 50_000_000;

    IVault vault;
    StrategyMendiLeverage strategy;
    VaultUser user;
    IStrategy constant PROD_STRAT = IStrategy(0x8754cEb960dFc194E87364ff958D443ac7Efd1ED);
    address unirouter = 0x1d0188c4B276A09366D05d6Be06aF61a73bC7535;
    IVToken market = IVToken(0x333D8b480BDB25eA7Be4Dd87EEB359988CE1b30D);
    IVToken altMarket = IVToken(0xf669C3C03D9fdF4339e19214A749E52616300E89);
    address USDT = 0xA219439258ca9da29E9Cc4cE5596924745e12B93;
    IComptroller comptroller = IComptroller(0x1b4d3b0421dDc1eB216D230Bc01527422Fb93103);
    uint256 borrowRate = 60;
    uint256 borrowRateMax = 77;
    uint256 borrowDepth = 4;
    uint256 minLeverage = 10000;
    address[] outputToNativeRoute = [0x43E8809ea748EFf3204ee01F08872F063e44065f,0x176211869cA2b568f2A7D4EE941E073a821EE1ff,0x0000000000000000000000000000000000000000];
    address[] outputToWantRoute = [0x43E8809ea748EFf3204ee01F08872F063e44065f,0x176211869cA2b568f2A7D4EE941E073a821EE1ff];

    function setUp() public {
        user = new VaultUser();
        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        vault = IVault(address(vaultV7));
        strategy = new StrategyMendiLeverage();

        vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);

        StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
            vault: address(vault),
            unirouter: unirouter,
            keeper: PROD_STRAT.keeper(),
            strategist: address(user),
            beefyFeeRecipient: PROD_STRAT.beefyFeeRecipient(),
            beefyFeeConfig: PROD_STRAT.beefyFeeConfig()
        });
        strategy.initialize(
            address(market), 
            borrowRate, 
            borrowRateMax, 
            borrowDepth, 
            minLeverage,
            outputToNativeRoute,
            outputToWantRoute,
            commons
        );
        console.log("Strategy initialized", IERC20Extended(strategy.want()).symbol());

        deal(vault.want(), address(user), wantAmount);
    }

    function test_prodHarvest() external {
        console.log("approving");
        user.approve(vault.want(), address(vault), wantAmount);
        console.log("approved");
        user.depositAll(vault);

        uint vaultBalance = vault.balance();
        uint pps = vault.getPricePerFullShare();
        uint lastHarvest = strategy.lastHarvest();

        skip(1 days);

        console.log("Harvesting vault");
        strategy.harvest();

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

    function test_rebalance() external {
        user.approve(vault.want(), address(vault), wantAmount);
        user.depositAll(vault);

        console.log("Rebalance to supply only");
        vm.prank(strategy.keeper());
        strategy.rebalance(0, 0, 0);

        console.log("Withdraw half of user balance");
        user.withdraw(vault, vault.balanceOf(address(user)) / 2);

        console.log("Deposit back in");
        user.approve(vault.want(), address(vault), wantAmount);
        user.depositAll(vault);

        console.log("Rebalance to high borrow rate");
        vm.prank(strategy.keeper());
        strategy.rebalance(70, 8, 10000);

        console.log("Harvest high borrow rate");
        skip(1 days);
        strategy.harvest();
        
        console.log("Panic");
        vm.prank(strategy.keeper());
        strategy.panic();

        console.log("Withdraw half of user balance");
        user.withdraw(vault, vault.balanceOf(address(user)) / 2);

        console.log("Unpause");
        vm.prank(strategy.keeper());
        strategy.unpause();

        console.log("Rebalance to normal rate");
        vm.prank(strategy.keeper());
        strategy.rebalance(60, 4, 10000);

        console.log("Deposit back in");
        user.approve(vault.want(), address(vault), wantAmount);
        user.depositAll(vault);

        console.log("Harvest normal rate");
        skip(1 days);
        strategy.harvest();
        
        console.log("Panic");
        vm.prank(strategy.keeper());
        strategy.panic();

        console.log("Withdraw half of user balance");
        user.withdraw(vault, vault.balanceOf(address(user)) / 2);

        console.log("Unpause");
        vm.prank(strategy.keeper());
        strategy.unpause();

        console.log("Deposit back in");
        user.approve(vault.want(), address(vault), wantAmount);
        user.depositAll(vault);
    }

    function test_low_liquidity() external {
        uint256 liquidity = IERC20(vault.want()).balanceOf(address(market));
        uint256 usdtToSupply = liquidity * 2;
        deal(USDT, address(user), usdtToSupply);
        user.approve(USDT, address(altMarket), usdtToSupply);

        vm.prank(address(user));
        altMarket.mint(usdtToSupply);
        vm.prank(address(user));
        address[] memory markets = new address[](1);
        markets[0] = address(altMarket);
        comptroller.enterMarkets(markets);
        vm.prank(address(user));
        market.borrow(liquidity);

        console.log("liquidity on market:", IERC20(vault.want()).balanceOf(address(market)));

        user.approve(vault.want(), address(vault), wantAmount);
        console.log("deposit in vault");
        user.deposit(vault, wantAmount);

        vm.prank(strategy.keeper());
        strategy.setWithdrawalFee(0);

        skip(1 days);

        console.log("PPFS before harvest:", vault.getPricePerFullShare());
        console.log("Harvesting vault");
        strategy.harvest();
        uint256 ppfsAfterHarvest = vault.getPricePerFullShare();
        console.log("PPFS after harvest:", ppfsAfterHarvest);

        liquidity = IERC20(vault.want()).balanceOf(address(market));
        vm.prank(address(user));
        market.borrow(liquidity / 2);

        console.log("Expect failure on full withdraw");
        vm.expectRevert();
        user.withdrawAll(vault);

        console.log("Withdraw some");
        user.withdraw(vault, wantAmount * 20 / 100);
        console.log("PPFS after withdrawal:", vault.getPricePerFullShare());

        console.log("Repay borrow");
        user.approve(vault.want(), address(market), wantAmount);
        vm.prank(address(user));
        market.repayBorrow(wantAmount);

        console.log("Expect success on full withdraw");
        user.withdrawAll(vault);
    }

    function test_ltv_drift() external {
        user.approve(vault.want(), address(vault), wantAmount);
        console.log("deposit in vault");
        user.deposit(vault, wantAmount);

        console.log("LTV started:", strategy.ltv());

        vm.prank(strategy.keeper());
        strategy.setWithdrawalFee(0);

        skip(10 days);

        console.log("Withdraw some");
        user.withdraw(vault, 1_000_000);

        console.log("LTV after withdraw:", strategy.ltv());

        vm.prank(strategy.keeper());
        strategy.harvest();

        console.log("LTV after harvest:", strategy.ltv());

        console.log("Withdraw some");
        user.withdraw(vault, 1_000_000);

        skip(10 days);

        vm.prank(strategy.keeper());
        strategy.harvest();

        console.log("LTV after harvest:", strategy.ltv());

        skip(10 days);

        user.approve(vault.want(), address(vault), 1_000_000);
        console.log("deposit in vault");
        user.deposit(vault, 1_000_000);

        console.log("LTV late deposit:", strategy.ltv());

        skip(10 days);

        user.approve(vault.want(), address(vault), 1_000_000);
        console.log("deposit in vault");
        user.deposit(vault, 1_000_000);

        console.log("LTV late deposit:", strategy.ltv());

        vm.prank(strategy.keeper());
        strategy.harvest();

        console.log("LTV after harvest:", strategy.ltv());

        skip(1000 days);

        console.log("Withdraw some");
        user.withdraw(vault, 1_000_000);
        console.log("LTV after long time:", strategy.ltv());

        vm.prank(strategy.keeper());
        strategy.panic();
        console.log("Supplied after panic:", strategy.supply());

        vm.prank(strategy.keeper());
        strategy.unpause();

        console.log("Harvest after long time");
        vm.prank(strategy.keeper());
        strategy.harvest();
        console.log("LTV after harvest after long time:", strategy.ltv());

        user.withdraw(vault, 40_000_000);
        console.log("LTV after withdraw:", strategy.ltv());
        console.log("PPFS after withdrawal:", vault.getPricePerFullShare());

        user.approve(vault.want(), address(vault), 40_000_000);
        console.log("deposit in vault");
        user.deposit(vault, 40_000_000);
        console.log("LTV after deposit:", strategy.ltv());

        vm.prank(strategy.keeper());
        strategy.panic();
        console.log("Supplied after panic:", strategy.supply());
    }
}