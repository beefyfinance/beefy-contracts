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
import "../interfaces/IUniV3Quoter.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/strategies/Gamma/StrategyThenaGamma.sol";
import "../../../contracts/BIFI/utils/AlgebraUtils.sol";
import "./BaseStrategyTest.t.sol";
//import "../vault/util/HardhatNetworkManager.sol";

contract StrategyThenaGammaTest is BaseStrategyTest {

    string constant chain = "bsc";

    IStrategy constant PROD_STRAT = IStrategy(0x01eD0C5f8b9E8845236E2fA87245DaD888337202);
    address constant native = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant the = 0xF4C8E32EaDEC4BFe97E0F595AdD0f4450a863a11;
    address constant unirouter = 0x327Dd3208f0bCF590A66110aCB6e5e6941A4EfA0;
    address constant wusdr = 0x2952beb1326acCbB5243725bd4Da2fC937BCa087;
    address constant bnbx = 0x1bdd3Cf7F79cfB8EdbB955f20ad99211551BA275;
    address constant usdc = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address constant usdt = 0x55d398326f99059fF775485246999027B3197955;
    address constant eth = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    address constant ankrBnb = 0x52F24a5e03aee338Da5fd9Df68D2b6FAe1178827;
    address constant stkBnb = 0xc2E9d07F66A89c44062459A47a0D2Dc038E4fb16;
    address constant btcb = 0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c;
    address constant floki = 0xfb5B838b6cfEEdC2873aB27866079AC55363D37E;
    address constant ankrETH = 0xe05A08226c49b636ACf99c40Da8DC6aF83CE5bB3;

    bytes outputToNative = AlgebraUtils.routeToPath(route(the, native));

    // WUSDR-DOLA
    address constant want = 0x92104a7BeC32297DdD022A8f242bf498d0470876;
    address constant rewardPool = 0x2174e40F56806D32f56Ad95202a4137B9F513E0b;
    address[] lp0Route = [native, usdt, usdc, wusdr];
    address[] lp1Route = [native, usdt, usdc, wusdr, 0x2F29Bc0FFAF9bff337b31CBe6CB5Fb3bf12e5840];
    bytes nativeToLp0 = AlgebraUtils.routeToPath(lp0Route);
    bytes nativeToLp1 = AlgebraUtils.routeToPath(lp1Route);

    // ETH-ankrETH
//    address constant want = 0x5c15842fCC12313C4f94dFB6fad1Af3f989D33e9;
//    address constant rewardPool = 0x5F8a5C3C094C6eb31d6b99B921dbB34a5151b352;
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(route(native, eth));
//    bytes nativeToLp1 = AlgebraUtils.routeToPath(route(native, eth, ankrETH));

    // USDT-FLOKI
//    address constant want = 0x2D65274C588C4f1f78Da0d288F69cb47C2FeFC3e;
//    address constant rewardPool = 0x19651F8d40123B58E91802A969d84434924ccbF0;
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(route(native, usdt));
//    bytes nativeToLp1 = AlgebraUtils.routeToPath(route(native, usdt, floki));

    // BTCB-BNB
//    address constant want = 0xD3C480EC7a47596fF8D63396227d1F7dC728A7f0;
//    address constant rewardPool = 0x65E40E779560199F5e68126Bc95bdc03083e5AA4;
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(route(native, btcb));
//    bytes nativeToLp1 = "";

    // ETH-BNB
//    address constant want = 0x10bf6e7B28b1cfFb1c047D7F815953931e5Ee947;
//    address constant rewardPool = 0xD777E84b0D29128351A35045D7AE728780dEf54D;
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(route(native, eth));
//    bytes nativeToLp1 = "";

    // USDT-BNB
//    address constant want = 0x3ec1FFd5dc29190588608Ae9Fd4f93750e84CDA2;
//    address constant rewardPool = 0x56996C3686E131A73E512d35308f348f987Bc0D5;
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(route(native, usdt));
//    bytes nativeToLp1 = "";

    // USDT-USDC
//    address constant want = 0x5EEca990E9B7489665F4B57D27D92c78BC2AfBF2;
//    address constant rewardPool = 0x1011530830c914970CAa96a52B9DA1C709Ea48fb;
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(route(native, usdt));
//    bytes nativeToLp1 = AlgebraUtils.routeToPath(route(native, usdt, usdc));

    // ankrBNB-BNB
//    address constant want = 0x754Fd74e22255780a58F125300008781D8318e3A;
//    address constant rewardPool = 0x8782fA8e2C973f7Cc19ce28DDf549fD9114F69dA;
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(route(native, ankrBnb));
//    bytes nativeToLp1 = "";

    // BNB-stkBNB
//    address constant want = 0x86b481fCe116DCd01fBeBb963f1358bcc466668C;
//    address constant rewardPool = 0x796472D20654D8751B481999204B623B264b004E;
//    bytes nativeToLp0 = "";
//    bytes nativeToLp1 = AlgebraUtils.routeToPath(route(native, stkBnb));

    // BNBx-BNB
//    address constant want = 0x2ecBD508c00Bbc8aA0cdc9100bf3956fCabE7677;
//    address constant rewardPool = 0xf50Af14BC4953Dcf9d27EbCA8BB3625855F5B42d;
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(route(native, bnbx));
//    bytes nativeToLp1 = "";

    // wUSDR-USDC
//    address constant want = 0x339685503dD534D27ce4a064314c2E5c7144aa92;
//    address constant rewardPool = 0xaD11A9034fB8657ebBB2FdD75f7254C2805F4981;
//    address[] lp0Route = [native, usdt, usdc, wusdr];
//    bytes nativeToLp0 = AlgebraUtils.routeToPath(lp0Route);
//    bytes nativeToLp1 = AlgebraUtils.routeToPath(route(native, usdt, usdc));

    IVault vault;
    StrategyThenaGamma strategy;
    VaultUser user;
    uint256 wantAmount = 50000 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyThenaGamma(vault.strategy());
            console.log("Testing vault at", vaultAddress);
            console.log(vault.name(), vault.symbol());
        } else {
            BeefyVaultV7 vaultV7 = new BeefyVaultV7();
            vault = IVault(address(vaultV7));
            StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
                vault: address(vault),
                unirouter: unirouter,
                keeper: PROD_STRAT.keeper(),
                strategist: address(user),
                beefyFeeRecipient: PROD_STRAT.beefyFeeRecipient(),
                beefyFeeConfig: PROD_STRAT.beefyFeeConfig()
            });
            strategy = new StrategyThenaGamma();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            strategy.initialize(want, rewardPool, outputToNative, nativeToLp0, nativeToLp1, commons);
        }

        console.log("outputToNative", bytesToStr(strategy.outputToNativePath()));
        console.log("nativeToLp0Path", bytesToStr(strategy.nativeToLp0Path()));
        console.log("nativeToLp1Path", bytesToStr(strategy.nativeToLp1Path()));

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

    function test_harvestRatio() external {
        _depositIntoVault(user, wantAmount);
        uint vaultBalance = vault.balance();
        console.log("Vault balance before harvest", vaultBalance);
        assertGe(vaultBalance, wantAmount, "Vault balance < wantAmount");

        skip(1 days);
        console.log("Harvesting vault");
        vm.prank(strategy.keeper());
        strategy.setFastQuote(false);
        strategy.harvest();
        console.log("Vault balance", strategy.balanceOfPool());
        assertGt(vault.balance(), vaultBalance, "Harvested 0");
        assertEq(IERC20(strategy.native()).balanceOf(address(strategy)), 0, "native balance != 0");
        assertEq(IERC20(strategy.lpToken0()).balanceOf(address(strategy)), 0, "lp0 balance != 0");
        assertEq(IERC20(strategy.lpToken1()).balanceOf(address(strategy)), 0, "lp1 balance != 0");
    }

    function test_harvestRatioFastQuote() external {
        _depositIntoVault(user, wantAmount);
        uint vaultBalance = vault.balance();
        console.log("Vault balance before harvest", vaultBalance);
        assertGe(vaultBalance, wantAmount, "Vault balance < wantAmount");

        skip(1 days);
        console.log("Harvesting vault");
        vm.prank(strategy.keeper());
        strategy.setFastQuote(true);
        strategy.harvest();
        console.log("Vault balance", strategy.balanceOfPool());
        assertGt(vault.balance(), vaultBalance, "Harvested 0");
        assertEq(IERC20(strategy.native()).balanceOf(address(strategy)), 0, "native balance != 0");
        assertEq(IERC20(strategy.lpToken0()).balanceOf(address(strategy)), 0, "lp0 balance != 0");
        assertEq(IERC20(strategy.lpToken1()).balanceOf(address(strategy)), 0, "lp1 balance != 0");
    }

}