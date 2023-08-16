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
import "../../../contracts/BIFI/strategies/Common/StrategyCommonSolidlyRewardPool.sol";
import "./BaseStrategyTest.t.sol";
import "../vault/util/AddressBook.sol";

contract StrategyPearl is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0xA8c0c2E089b8606f5bC591C4980106E46c329D68);
    address constant native = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address constant output = 0x7238390d5f6F64e67c3211C343A410E2A3DEc142;
    address constant usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant usdr = 0x40379a439D4F6795B6fc9aa5687dB461677A2dBa;
    address constant dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant unirouter = 0x06374F57991CDc836E5A318569A910FE6456D230;

    // USDR-TNGBL
    address constant want = 0x0Edc235693C20943780b76D79DD763236E94C751;
    address constant gauge = 0xdaeF32cA8D699015fcFB2884F6902fFCebE51c5b;
    // WBTC-USDR
//    address constant want = 0xb95E1C22dd965FafE926b2A793e9D6757b6613F4;
//    address constant gauge = 0x39976f6328ebA2a3C860b7DE5cF2c1bB41581FB8;
    // USDR-ETH
//    address constant want = 0x74c64d1976157E7Aaeeed46EF04705F4424b27eC;
//    address constant gauge = 0x7D02A8b758791A03319102f81bF61E220F73e43D;
    // MATIC-USDR
//    address constant want = 0xB4d852b92148eAA16467295975167e640E1FE57A;
//    address constant gauge = 0xdA0AfBeEEBef6dA2F060237D35cab759b99B13B6;
    // wUSDR-USDR
//    address constant want = 0x8711a1a52c34EDe8E61eF40496ab2618a8F6EA4B;
//    address constant gauge = 0x03Fa7A2628D63985bDFe07B95d4026663ED96065;
    // USDR-USDT
//    address constant want = 0x3f69055F203861abFd5D986dC81a2eFa7c915b0c;
//    address constant gauge = 0x89EF6e539F2Ac4eE817202f445aA69A3769A727C;
    // USDR-DAI
//    address constant want = 0xBD02973b441Aa83c8EecEA158b98B5984bb1036E;
//    address constant gauge = 0x85Fa2331040933A02b154579fAbE6A6a5A765279;
    // USDC-USDR
//    address constant want = 0xD17cb0f162f133e339C0BbFc18c36c357E681D6b;
//    address constant gauge = 0x97Bd59A8202F8263C2eC39cf6cF6B438D0B45876;

    function routes() internal view returns (
        ISolidlyRouter.Routes[] memory outputToNative,
        ISolidlyRouter.Routes[] memory outputToLp0,
        ISolidlyRouter.Routes[] memory outputToLp1
    ) {
        bool stable = ISolidlyPair(want).stable();
        address t0 = ISolidlyPair(want).token0();
        address t1 = ISolidlyPair(want).token1();

        outputToNative = new ISolidlyRouter.Routes[](2);
        outputToNative[0] = ISolidlyRouter.Routes(output, usdr, false);
        outputToNative[1] = ISolidlyRouter.Routes(usdr, native, false);

        if (t0 == usdr) {
            outputToLp0 = new ISolidlyRouter.Routes[](1);
            outputToLp0[0] = ISolidlyRouter.Routes(output, usdr, false);

            outputToLp1 = new ISolidlyRouter.Routes[](2);
            outputToLp1[0] = ISolidlyRouter.Routes(output, usdr, false);
            outputToLp1[1] = ISolidlyRouter.Routes(usdr, t1, stable);
        } else {
            outputToLp0 = new ISolidlyRouter.Routes[](2);
            outputToLp0[0] = ISolidlyRouter.Routes(output, usdr, false);
            outputToLp0[1] = ISolidlyRouter.Routes(usdr, t0, stable);

            outputToLp1 = new ISolidlyRouter.Routes[](1);
            outputToLp1[0] = ISolidlyRouter.Routes(output, usdr, false);
        }
    }

    IVault vault;
    StrategyCommonSolidlyRewardPoolLP strategy;
    VaultUser user;
    uint256 wantAmount = 50 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyCommonSolidlyRewardPoolLP(vault.strategy());
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
            strategy = new StrategyCommonSolidlyRewardPoolLP();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            (ISolidlyRouter.Routes[] memory outputToNative, ISolidlyRouter.Routes[] memory outputToLp0, ISolidlyRouter.Routes[] memory outputToLp1) = routes();
            strategy.initialize(want, gauge, commons, outputToNative, outputToLp0, outputToLp1);
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

    function test_printRoutes() public view {
        (, ISolidlyRouter.Routes[] memory outputToLp0, ISolidlyRouter.Routes[] memory outputToLp1) = routes();
        address t0 = ISolidlyPair(want).token0();
        address t1 = ISolidlyPair(want).token1();
        string memory t0s = t0 == usdr ? 'USDRv3' : IERC20Extended(t0).symbol();
        string memory t1s = t1 == usdr ? 'USDRv3' : IERC20Extended(t1).symbol();

        console.log(string.concat('mooName: "Moo Pearl ', t0s, '-', t1s, '",'));
        console.log(string.concat('mooSymbol: "mooPearl', t0s, '-', t1s, '",'));
        console.log(string.concat('want: "', addrToStr(want), '",'));
        console.log(string.concat('gauge: "', addrToStr(gauge), '",'));
        console.log('outputToLp0:', string.concat(solidRouteToStr(outputToLp0), ','));
        console.log('outputToLp1:', string.concat(solidRouteToStr(outputToLp1), ','));
    }

    function solidRouteToStr(ISolidlyRouter.Routes[] memory a) public pure returns (string memory t) {
        if (a.length == 0) return "[[]]";
        if (a.length == 1) return string.concat('[["', addrToStr(a[0].from), '", "', addrToStr(a[0].to), '", ', boolToStr(a[0].stable), ']]');
        t = string.concat('[["', addrToStr(a[0].from), '", "', addrToStr(a[0].to), '", ', boolToStr(a[0].stable), ']');
        for (uint i = 1; i < a.length; i++) {
            t = string.concat(t, ", ", string.concat('["', addrToStr(a[i].from), '", "', addrToStr(a[i].to), '", ', boolToStr(a[i].stable), ']'));
        }
        t = string.concat(t, "]");
    }
}