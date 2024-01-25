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
import "../../../contracts/BIFI/strategies/Velodrome/StrategyVelodromeUsdPlus.sol";
import "../../../contracts/BIFI/interfaces/velodrome-v2/IVoter.sol";
import "../../../contracts/BIFI/interfaces/velodrome-v2/IPool.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyVelodromeUsdPlusTest is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0x61cc42C162E0B19F521b7ab963E0Bd8Cc219E8aA);
    address constant native = 0x4200000000000000000000000000000000000006;
    address constant output = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant unirouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    IVoter constant voter = IVoter(0x16613524e02ad97eDfeF371bC883F2F5d6C480A5);
    address factory = ISolidlyRouter(unirouter).defaultFactory();
    address constant usdbc = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address constant usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant usdPlus = 0xB79DD08EA68A908A97220C76d19A6aA9cBDE4376;
    address constant usdExchange = 0x7cb1B38591021309C64f451859d79312d8Ca2789;

    // ovn-usd+
    address constant want = 0x61366A4e6b1DB1b85DD701f2f4BFa275EF271197;
    address constant gauge = 0x00B2149d89677a5069eD4D303941614A33700146;

    function routes() internal view returns (
        ISolidlyRouter.Route[] memory outputToNative,
        ISolidlyRouter.Route[] memory outputToUsdBc,
        ISolidlyRouter.Route[] memory usdPlusToLp0,
        ISolidlyRouter.Route[] memory usdPlusToLp1
    ) {
        bool stable = ISolidlyPair(want).stable();
        address t0 = ISolidlyPair(want).token0();
        address t1 = ISolidlyPair(want).token1();

        outputToNative = new ISolidlyRouter.Route[](1);
        outputToNative[0] = ISolidlyRouter.Route(output, native, false, address(0));
        outputToUsdBc = new ISolidlyRouter.Route[](1);
        ISolidlyRouter.Route[] memory outputToUsdc = new ISolidlyRouter.Route[](1);
        outputToUsdBc[0] = ISolidlyRouter.Route(output, usdbc, false, address(0));
        outputToUsdc[0] = ISolidlyRouter.Route(output, usdc, false, address(0));

        usdPlusToLp0 = new ISolidlyRouter.Route[](1);
        usdPlusToLp1 = new ISolidlyRouter.Route[](1);
        if (t0 == usdPlus) {
            usdPlusToLp0[0] = ISolidlyRouter.Route(t0, t1, stable, address(0));
            usdPlusToLp1[0] = ISolidlyRouter.Route(t0, t1, stable, address(0));
        } else {
            usdPlusToLp0[0] = ISolidlyRouter.Route(t1, t0, stable, address(0));
            usdPlusToLp1[0] = ISolidlyRouter.Route(t1, t0, stable, address(0));
        }
    }

    IVault vault;
    StrategyVelodromeUsdPlus strategy;
    VaultUser user;
    uint256 wantAmount = 50 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyVelodromeUsdPlus(vault.strategy());
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
            strategy = new StrategyVelodromeUsdPlus();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            (ISolidlyRouter.Route[] memory outputToNative, ISolidlyRouter.Route[] memory outputToUsdBc, ISolidlyRouter.Route[] memory usdPlusToLp0, ISolidlyRouter.Route[] memory usdPlusToLp1) = routes();
            strategy.initialize(want, gauge, usdExchange, commons, outputToNative, outputToUsdBc, usdPlusToLp0, usdPlusToLp1);
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

    function test_printRoutes() public view {
        (,ISolidlyRouter.Route[] memory outputToUsdc, ISolidlyRouter.Route[] memory outputToLp0, ISolidlyRouter.Route[] memory outputToLp1) = routes();
        string memory t0s = IERC20Extended(ISolidlyPair(want).token0()).symbol();
        string memory t1s = IERC20Extended(ISolidlyPair(want).token1()).symbol();

        console.log(string.concat('mooName: "Moo Aero ', t0s, '-', t1s, '",'));
        console.log(string.concat('mooSymbol: "mooAero', t0s, '-', t1s, '",'));
        console.log(string.concat('want: "', addrToStr(want), '",'));
        console.log(string.concat('gauge: "', addrToStr(gauge), '",'));
        console.log('outputToUsdc:', string.concat(solidRouteToStr(outputToUsdc), ','));
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