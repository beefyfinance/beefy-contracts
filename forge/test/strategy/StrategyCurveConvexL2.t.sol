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
import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvexL2.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/utils/UniswapV3Utils.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCurveConvexL2Test is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0x61cc42C162E0B19F521b7ab963E0Bd8Cc219E8aA);
    address public native = PROD_STRAT.native();
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant crv = 0x8Ee73c484A26e0A5df2Ee2a4960B789967dd0415;
    address constant curveRouter = 0xC02b26ba08c3507D46E5c45fA09FEf44a7C5378d;

    address constant usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant cbEth = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
    address constant baseCrvCrvUSDPool = 0xDE37E221442Fa15C35dc19FbAE11Ed106ba52fB2;
    address constant baseCrvUSD = 0x417Ac0e078398C154EdFadD9Ef675d30Be60Af93;
    address constant baseTriCrypto = 0x6e53131F68a034873b6bFA15502aF094Ef0c5854;

    address constant uniV3 = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant uniV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address a0 = address(0);
    uint24[] fee500 = [500];
    uint24[] fee3000 = [3000];
    uint24[] fee10000 = [10000];
    uint24[] fee10000_500 = [10000, 500];


    // crv-crvusd
    address want = 0x6DfE79cecE4f64c1a34F48cF5802492aB595257E;
    address gauge = 0x89289DC2192914a9F0674f1E9A17C56456549b8A;
    uint pid = 42069;
    bytes nativeToDepositPath = "";
    address[9] depositToWant = [native, baseTriCrypto, baseCrvUSD, baseCrvCrvUSDPool, want];
    uint[3][4] depositToWantParams = [[2,0,3], [1,0,7]];

    // 4-pool
//    address want = 0xf6C5F01C7F3148891ad0e19DF78743D31E390D1f;
//    address gauge = 0x79edc58C471Acf2244B8f93d6f425fD06A439407;
//    uint pid = 42069;
//    bytes nativeToDepositPath = "";
//    address[9] depositToWant = [native, baseTriCrypto, baseCrvUSD, want, want];
//    uint[3][4] depositToWantParams = [[2,0,3], [3,0,10]];

    // TriCrypto
//    address want = 0x6e53131F68a034873b6bFA15502aF094Ef0c5854;
//    address gauge = 0x93933FA992927284e9d508339153B31eb871e1f4;
//    uint pid = 42069;
//    bytes nativeToDepositPath = "";
//    address[9] depositToWant = [native, want, want];
//    uint[3][4] depositToWantParams = [[2,0,8]];

    // cbETH-ETH
//    address want = 0x98244d93D42b42aB3E3A4D12A5dc0B3e7f8F32f9;
//    address gauge = 0xE9c898BA654deC2bA440392028D2e7A194E6dc3e;
//    uint pid = 42069;
//    bytes nativeToDepositPath = "";
//    address[9] depositToWant = [native, 0x11C1fBd4b3De66bC0565779b35171a6CF3E71f59, want];
//    uint[3][4] depositToWantParams = [[0,0,7]];

    StrategyCurveConvexL2.CurveRoute depositToWantRoute = StrategyCurveConvexL2.CurveRoute(
        depositToWant, depositToWantParams, 0);

    address unirouter = uniV3;
    address[] rewardsV3;
    uint24[] rewardsV3Fee = fee10000_500;

    address[9] crvToNative = [crv, baseCrvCrvUSDPool, baseCrvUSD, baseTriCrypto, native];
    uint[3][4] crvParams = [[0, 1, 3], [0, 2, 3]];
    StrategyCurveConvexL2.CurveRoute crvToNativeRoute = StrategyCurveConvexL2.CurveRoute(crvToNative, crvParams, 0);

    IVault vault;
    StrategyCurveConvexL2 strategy;
    VaultUser user;
    uint256 wantAmount = 50000 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyCurveConvexL2(vault.strategy());
            console.log("Testing vault at", vaultAddress);
            console.log(vault.name(), vault.symbol());
        } else {
            BeefyVaultV7 vaultV7 = new BeefyVaultV7();
            vault = IVault(address(vaultV7));
            strategy = new StrategyCurveConvexL2();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
                vault: address(vault),
                unirouter: unirouter,
                keeper: PROD_STRAT.keeper(),
                strategist: address(user),
                beefyFeeRecipient: PROD_STRAT.beefyFeeRecipient(),
                beefyFeeConfig: PROD_STRAT.beefyFeeConfig()
            });
            strategy.initialize(native, curveRouter, want, gauge, pid, nativeToDepositPath, crvToNativeRoute, depositToWantRoute, commons);
            console.log("Strategy initialized", IERC20Extended(strategy.want()).symbol(), strategy.pid(), strategy.rewardPool());

            if (nativeToDepositPath.length > 0) {
                console.log("nativeToDeposit", bytesToStr(nativeToDepositPath));
            }

            if (rewardsV3.length > 0) {
                bytes memory path = routeToPath(rewardsV3, rewardsV3Fee);
                console.log("RewardV3", IERC20Extended(rewardsV3[0]).symbol(), bytesToStr(path));
                strategy.addRewardV3(path, 1000);
            }
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

    function test_initWithNoPid() external {
        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        IVault vaultNoPid = IVault(address(vaultV7));
        StrategyCurveConvexL2 strategyNoPid = new StrategyCurveConvexL2();

        deal(want, address(user), wantAmount);

        vaultV7.initialize(IStrategyV7(address(strategyNoPid)), "TestVault", "testVault", 0);
        StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
            vault : address(vaultNoPid),
            unirouter : unirouter,
            keeper : PROD_STRAT.keeper(),
            strategist : address(user),
            beefyFeeRecipient : PROD_STRAT.beefyFeeRecipient(),
            beefyFeeConfig : PROD_STRAT.beefyFeeConfig()
        });
        console.log("Init Strategy NO_PID");
        strategyNoPid.initialize(native, curveRouter, want, gauge, strategy.NO_PID(), nativeToDepositPath, crvToNativeRoute, depositToWantRoute, commons);

        user.approve(want, address(vaultNoPid), wantAmount);
        user.depositAll(vaultNoPid);
        user.withdrawAll(vaultNoPid);
        uint wantBalanceFinal = IERC20(want).balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, wantAmount, "Expected wantBalanceFinal <= wantAmount");
        assertGt(wantBalanceFinal, wantAmount * 99 / 100, "Expected wantBalanceFinal > wantAmount * 99 / 100");
    }

    function test_setConvexPid() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        address rewardPool = strategy.rewardPool();
        _depositIntoVault(user, wantAmount);

        uint rewardPoolBal = IConvexRewardPool(rewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");

        console.log("setConvexPid NO_PID switches to Curve");
        strategy.setConvexPid(strategy.NO_PID());
        rewardPoolBal = IConvexRewardPool(rewardPool).balanceOf(address(strategy));
        assertEq(rewardPoolBal, 0, "RewardPool balance != 0");
        uint gaugeBal = IRewardsGauge(strategy.gauge()).balanceOf(address(strategy));
        assertEq(vault.balance(), gaugeBal, "Gauge balance != vault balance");
        user.withdrawAll(vault);
        uint userBal = IERC20(want).balanceOf(address(user));
        assertLe(userBal, wantAmount, "Expected userBal <= wantAmount");
        assertGt(userBal, wantAmount * 99 / 100, "Expected userBal > wantAmount * 99 / 100");

        _depositIntoVault(user, userBal);
        console.log("setConvexPid bad pid reverts");
        vm.expectRevert();
        strategy.setConvexPid(1);

        console.log("setConvexPid valid pid switches to Convex");
        strategy.setConvexPid(pid);
        rewardPoolBal = IConvexRewardPool(rewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");
        gaugeBal = IRewardsGauge(strategy.gauge()).balanceOf(address(strategy));
        assertEq(gaugeBal, 0, "Gauge balance != 0");
        user.withdrawAll(vault);
        uint userBalFinal = IERC20(want).balanceOf(address(user));
        assertLe(userBalFinal, userBal, "Expected userBalFinal <= userBal");
        assertGt(userBalFinal, userBal * 99 / 100, "Expected userBalFinal > userBal * 99 / 100");
    }

    function test_setNativeToDepositPath() external {
        console.log("Non-native path reverts");
        vm.expectRevert();
        strategy.setNativeToDepositPath(routeToPath(route(usdc, native), fee3000));
    }

    function test_setDepositToWant() external {
        vm.startPrank(strategy.keeper());
        uint[3][4] memory p;
        console.log("Want as deposit token reverts");
        address w = strategy.want();
        vm.expectRevert();
        strategy.setDepositToWant([w, a0, a0, a0, a0, a0, a0, a0, a0], p, 1e18);

        console.log("Deposit token approved on curve router");
        address token = native;
        strategy.setDepositToWant([token, a0, a0, a0, a0, a0, a0, a0, a0], p, 1e18);
        uint allowed = IERC20(token).allowance(address(strategy), strategy.curveRouter());
        assertEq(allowed, type(uint).max);
    }

    function test_setCrvMintable() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        _depositIntoVault(user, wantAmount);
        uint bal = vault.balance();

        console.log("setConvexPid NO_PID");
        strategy.setConvexPid(strategy.NO_PID());

        console.log("setCrvMintable false not expecting harvest");
        skip(1 days);
        strategy.setCrvMintable(false);
        strategy.harvest();
        assertEq(vault.balance(), bal, "Harvested");

        console.log("setCrvMintable true expecting harvest CRV");
        skip(1 days);
        strategy.setCrvMintable(true);
        strategy.harvest();
        assertGt(vault.balance(), bal, "Not harvested");
    }

    function test_addRewards() external {
        vm.startPrank(strategy.keeper());
        strategy.resetCurveRewards();
        strategy.resetRewardsV3();

        console.log("Add curveReward");
        uint[3] memory p = [uint(1),uint(0), uint(0)];
        uint[3][4] memory _params = [p,p,p,p];
        strategy.addReward([crv,a0,a0,a0,a0,a0,a0,a0,a0], _params, 1);
        (address[9] memory r, uint256[3][4] memory params, uint minAmount) = strategy.curveReward(0);
        address token0 = r[0];
        assertEq(token0, crv, "!crv");
        assertEq(params[0][0], _params[0][0], "!params");
        assertEq(minAmount, 1, "!minAmount");
        vm.expectRevert();
        strategy.curveRewards(2);

        console.log("Add rewardV3");
        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;
        strategy.addRewardV3(routeToPath(route(crv, strategy.native()), fees), 1);
        (token0,,minAmount) = strategy.rewardsV3(0);
        assertEq(token0, crv, "!crv");
        assertEq(minAmount, 1, "!minAmount");
        vm.expectRevert();
        strategy.rewardsV3(1);


        console.log("rewardV3Route");
        print(strategy.rewardV3Route(0));
        console.log("nativeToDeposit");
        bytes memory path = strategy.nativeToDepositPath();
        if (path.length > 0) {
            print(UniswapV3Utils.pathToRoute(path));
        }
        console.log("depositToWant");
        (r, params, minAmount) = strategy.depositToWantRoute();
        for(uint i; i < r.length; i++) {
            if (r[i] == address(0)) break;
            console.log(r[i]);
        }

        strategy.resetCurveRewards();
        strategy.resetRewardsV3();
        vm.expectRevert();
        strategy.rewardsV3(0);
        vm.expectRevert();
        strategy.curveRewards(0);
    }

    function test_rewards() external {
        _depositIntoVault(user, wantAmount);
        skip(1 days);

        // only if convex
        if (strategy.rewardPool() != address(0)) {
            uint rewardsAvailable = strategy.rewardsAvailable();
            assertGt(rewardsAvailable, 0, "Expected rewardsAvailable > 0");
        }

        address[] memory rewards = new address[](strategy.curveRewardsLength() + strategy.rewardsV3Length());
        for(uint i; i < strategy.curveRewardsLength(); ++i) {
            (address[9] memory route,,) = strategy.curveReward(i);
            rewards[i] = route[0];
        }
        for(uint i; i < strategy.rewardsV3Length(); ++i) {
            rewards[strategy.curveRewardsLength() + i] = strategy.rewardV3Route(i)[0];
            (address token, bytes memory path,) = strategy.rewardsV3(i);
            uint out = IUniV3Quoter(uniV3Quoter).quoteExactInput(path, 1e20);
            console.log("Route 100", IERC20Extended(token).symbol(), "to ETH:", out);
        }

        // if convex
        if (strategy.rewardPool() != address(0)) {
            console.log("Claim rewards on Convex");
            IConvexRewardPool(strategy.rewardPool()).getReward(address(strategy), true);
            for (uint i; i < rewards.length; ++i) {
                string memory s = IERC20Extended(rewards[i]).symbol();
                console2.log(s, IERC20(rewards[i]).balanceOf(address(strategy)));
            }
            console.log("WETH", IERC20(native).balanceOf(address(strategy)));
            deal(crv, address(strategy), 1e20);
        } else {
            console.log("Claim rewards on Curve");
            if (strategy.isCurveRewardsClaimable()) {
                IRewardsGauge(strategy.gauge()).claim_rewards(address(strategy));
            }
            if (strategy.isCrvMintable()) {
                strategy.minter().mint(strategy.gauge());
            }
            for (uint i; i < rewards.length; ++i) {
                string memory s = IERC20Extended(rewards[i]).symbol();
                console2.log(s, IERC20(rewards[i]).balanceOf(address(strategy)));
            }
        }

        console.log("Harvest");
        strategy.harvest();
        for (uint i; i < rewards.length; ++i) {
            string memory s = IERC20Extended(rewards[i]).symbol();
            uint bal = IERC20(rewards[i]).balanceOf(address(strategy));
            console2.log(s, bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
        uint nativeBal = IERC20(native).balanceOf(address(strategy));
        console.log("WETH", nativeBal);
        assertEq(nativeBal, 0, "Native not swapped");
    }

    function test_printRoutes() public view {
        string memory symbol = IERC20Extended(want).symbol();
        console.log(string.concat('mooName: "Moo Curve ', symbol, '",'));
        console.log(string.concat('mooSymbol: "mooCurve', symbol, '",'));
        console.log(string.concat('want: "', addrToStr(want), '",'));
        console.log(string.concat('gauge: "', addrToStr(gauge), '",'));
        console.log(string.concat('pid: ', vm.toString(pid), ','));
        console.log(string.concat('nativeToDeposit: "', bytesToStr(nativeToDepositPath), '",'));
        console.log('depositToWant:', string.concat(curveRouteToStr(depositToWantRoute), ','));
        console.log('crvToNative:', string.concat(curveRouteToStr(crvToNativeRoute), ','));
    }

    function curveRouteToStr(StrategyCurveConvexL2.CurveRoute memory a) public pure returns (string memory t) {
        t = string.concat('[\n["', addrToStr(a.route[0]), '"');
        for (uint i = 1; i < a.route.length; i++) {
            t = string.concat(t, ", ", string.concat('"', addrToStr(a.route[i]), '"'));
        }
        t = string.concat(t, '],\n[', uintsToStr(a.swapParams[0]));
        for (uint i = 1; i < a.swapParams.length; i++) {
            t = string.concat(t, ", ", uintsToStr(a.swapParams[i]));
        }
        t = string.concat(t, '],\n', vm.toString(a.minAmount), '\n]');
    }
}