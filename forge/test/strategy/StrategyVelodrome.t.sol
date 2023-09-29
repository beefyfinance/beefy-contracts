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
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/strategies/Velodrome/StrategyVelodromeGaugeV2.sol";
import "../../../contracts/BIFI/interfaces/velodrome-v2/IVoter.sol";
import "../../../contracts/BIFI/interfaces/velodrome-v2/IPool.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyVelodrome is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0x61cc42C162E0B19F521b7ab963E0Bd8Cc219E8aA);
    address constant native = 0x4200000000000000000000000000000000000006;
    address constant output = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant unirouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    IVoter constant voter = IVoter(0x16613524e02ad97eDfeF371bC883F2F5d6C480A5);
    address factory = ISolidlyRouter(unirouter).defaultFactory();
    address constant usdc = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;

    // ovn-usd+
    address constant want = 0x61366A4e6b1DB1b85DD701f2f4BFa275EF271197;
    address constant gauge = 0x00B2149d89677a5069eD4D303941614A33700146;

    // DAI-USDbC
//    address constant want = 0x6EAB8c1B93f5799daDf2C687a30230a540DbD636;
//    address constant gauge = 0xCF1D5Aa63083fda05c7f8871a9fDbfed7bA49060;

//    "name": "aerodrome-wusdr-usdbc",
//    address constant want = 0x3Fc28BFac25fC8e93B5b2fc15EfBBD5a8aA44eFe;
//    address constant gauge = 0xF64957C35409055776C7122AC655347ef88eaF9B;

    // name": "aerodrome-aero-usdbc",
//    address constant want = 0x2223F9FE624F69Da4D8256A7bCc9104FBA7F8f75;
//    address constant gauge = 0x9a202c932453fB3d04003979B121E80e5A14eE7b;

//"name": "aerodrome-weth-aero",
//    address constant want = 0x7f670f78B17dEC44d5Ef68a48740b6f8849cc2e6;
//    address constant gauge = 0x96a24aB830D4ec8b1F6f04Ceac104F1A3b211a01;

//"name": "aerodrome-cbeth-weth",
//    address constant want = 0x44Ecc644449fC3a9858d2007CaA8CFAa4C561f91;
//    address constant gauge = 0xDf9D427711CCE46b52fEB6B2a20e4aEaeA12B2b7;

//"name": "aerodrome-weth-usdbc",
//    address constant want = 0xB4885Bc63399BF5518b994c1d0C153334Ee579D0;
//    address constant gauge = 0xeca7Ff920E7162334634c721133F3183B83B0323;

// "name": "aerodrome-mai-usdbc",
//    address constant want = 0xf6Aec4F97623E691a9426a69BaF5501509fCa05D;
//    address constant gauge = 0xC01E2ff20501839db7B28F5Cb3eD2876fEa3d6b1;

//"name": "aerodrome-dola-usdbc",
//    address constant want = 0x0B25c51637c43decd6CC1C1e3da4518D54ddb528;
//    address constant gauge = 0xeAE066C25106006fB386A3a8b1698A0cB6931c1a;

//"name": "aerodrome-dola-mai",
//    address constant want = 0x8b432C54d6e8E1B8D1802753514AB53044Af1861;
//    address constant gauge = 0xDe23611176b16720346f4Df071D1aA01752c68C1;

    function routes() internal view returns (
        ISolidlyRouter.Route[] memory outputToNative,
        ISolidlyRouter.Route[] memory outputToLp0,
        ISolidlyRouter.Route[] memory outputToLp1
    ) {
        bool stable = ISolidlyPair(want).stable();
        address t0 = ISolidlyPair(want).token0();
        address t1 = ISolidlyPair(want).token1();

        outputToNative = new ISolidlyRouter.Route[](1);
        outputToNative[0] = ISolidlyRouter.Route(output, native, false, factory);
        ISolidlyRouter.Route[] memory outputToUsdc = new ISolidlyRouter.Route[](1);
        outputToUsdc[0] = ISolidlyRouter.Route(output, usdc, false, factory);

        if (t0 == output) outputToLp0 = new ISolidlyRouter.Route[](0);
        else if (t0 == native) outputToLp0 = outputToNative;
        else if (t0 == usdc) outputToLp0 = outputToUsdc;
        else {
            outputToLp0 = new ISolidlyRouter.Route[](2);
            if (t1 == native) {
                outputToLp0[0] = outputToNative[0];
                outputToLp0[1] = ISolidlyRouter.Route(native, t0, stable, factory);
            } else if (t1 == usdc) {
                outputToLp0[0] = outputToUsdc[0];
                outputToLp0[1] = ISolidlyRouter.Route(usdc, t0, stable, factory);
            } else {
                // manual per want
                outputToLp0 = new ISolidlyRouter.Route[](3);
                outputToLp0[0] = outputToUsdc[0];
                outputToLp0[1] = ISolidlyRouter.Route(usdc, t1, true, factory);
                outputToLp0[2] = ISolidlyRouter.Route(t1, t0, false, factory);
            }
        }

        if (t1 == output) outputToLp1 = new ISolidlyRouter.Route[](0);
        else if (t1 == native) outputToLp1 = outputToNative;
        else if (t1 == usdc) outputToLp1 = outputToUsdc;
        else {
            outputToLp1 = new ISolidlyRouter.Route[](2);
            if (t0 == native) {
                outputToLp1[0] = outputToNative[0];
                outputToLp1[1] = ISolidlyRouter.Route(native, t1, stable, factory);
            } else if (t0 == usdc) {
                outputToLp1[0] = outputToUsdc[0];
                outputToLp1[1] = ISolidlyRouter.Route(usdc, t1, stable, factory);
            } else {
                // manual per want
                outputToLp1 = new ISolidlyRouter.Route[](2);
                outputToLp1[0] = outputToUsdc[0];
                outputToLp1[1] = ISolidlyRouter.Route(usdc, t1, true, factory);
            }
        }
    }

    IVault vault;
    StrategyVelodromeGaugeV2 strategy;
    VaultUser user;
    uint256 wantAmount = 50 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyVelodromeGaugeV2(vault.strategy());
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
            strategy = new StrategyVelodromeGaugeV2();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            (ISolidlyRouter.Route[] memory outputToNative, ISolidlyRouter.Route[] memory outputToLp0, ISolidlyRouter.Route[] memory outputToLp1) = routes();
            strategy.initialize(want, gauge, commons, outputToNative, outputToLp0, outputToLp1);
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));

//        skip(1 weeks);
//        address[] memory gauges = new address[](1);
//        gauges[0] = strategy.gauge();
//        voter.distribute(gauges);
//        address aeroUsdcLp = 0x2223F9FE624F69Da4D8256A7bCc9104FBA7F8f75;
//        address aeroEthLP = 0x7f670f78B17dEC44d5Ef68a48740b6f8849cc2e6;
//        deal(output, aeroUsdcLp, 1_000_000 * 1e18);
//        deal(usdc, aeroUsdcLp, 1_000_000 * 1e6);
//        deal(output, aeroEthLP, 1_000_000 * 1e18);
//        deal(native, aeroEthLP, 600 * 1e18);
//        IPool(aeroUsdcLp).mint(address(1));
//        IPool(aeroEthLP).mint(address(1));
    }

    function test_printRoutes() public view {
        (, ISolidlyRouter.Route[] memory outputToLp0, ISolidlyRouter.Route[] memory outputToLp1) = routes();
        string memory t0s = IERC20Extended(ISolidlyPair(want).token0()).symbol();
        string memory t1s = IERC20Extended(ISolidlyPair(want).token1()).symbol();

        console.log(string.concat('mooName: "Moo Aero ', t0s, '-', t1s, '",'));
        console.log(string.concat('mooSymbol: "mooAero', t0s, '-', t1s, '",'));
        console.log(string.concat('want: "', addrToStr(want), '",'));
        console.log(string.concat('gauge: "', addrToStr(gauge), '",'));
        console.log('outputToLp0:', string.concat(solidRouteToStr(outputToLp0), ','));
        console.log('outputToLp1:', string.concat(solidRouteToStr(outputToLp1), ','));
    }

    function solidRouteToStr(ISolidlyRouter.Route[] memory a) public view returns (string memory t) {
        if (a.length == 0) return "[[]]";
        if (a.length == 1) return string.concat('[["', addrToStr(a[0].from), '", "', addrToStr(a[0].to), '", ', boolToStr(a[0].stable), ', "', addrToStr(factory), '"', ']]');
        t = string.concat('[["', addrToStr(a[0].from), '", "', addrToStr(a[0].to), '", ', boolToStr(a[0].stable), ', "', addrToStr(factory), '"', ']');
        for (uint i = 1; i < a.length; i++) {
            t = string.concat(t, ", ", string.concat('["', addrToStr(a[i].from), '", "', addrToStr(a[i].to), '", ', boolToStr(a[i].stable), ', "', addrToStr(factory), '"', ']'));
        }
        t = string.concat(t, "]");
    }
}