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
import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvex.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/utils/UniswapV3Utils.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCurveConvexTest is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0x2486c5fa59Ba480F604D5A99A6DAF3ef8A5b4D76);
    address constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant triCrypto = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address constant usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant crv3pool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address constant crv3poolLp = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant fraxBp = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2;
    address constant fraxBpLp = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC;
    address constant tbtc = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
    address constant wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant sbtcPool = 0xf253f83AcA21aAbD2A20553AE0BF7F65C755A07F;
    address constant sbtcLp = 0x051d7e5609917Bd9b73f04BAc0DED8Dd46a74301;

    address constant uniV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant uniV2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant uniV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    ICrvMinter public constant minter = ICrvMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    address a0 = address(0);
    uint24[] fee500 = [500];
    uint24[] fee3000 = [3000];
    uint24[] fee10000 = [10000];
    uint24[] fee10000_500 = [10000, 500];
    bytes crvToNativeUniV3 = routeToPath(route(crv, native), fee3000);
    bytes cvxToNativeUniV3 = routeToPath(route(cvx, native), fee10000);

    // crvUSD-USDC
//    address want = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
//    address gauge = 0x95f00391cB5EebCd190EB58728B4CE23DbFa6ac1;
//    uint pid = 182;
//    bytes crvToNativePath = crvToNativeUniV3;
//    bytes cvxToNativePath = cvxToNativeUniV3;
//    bytes nativeToDepositPath = routeToPath(route(native, usdc), fee500);
//    address[9] depositToWant = [usdc, want, want];
//    uint[3][4] depositToWantParams = [[0,0,7]];
//    address unirouter = uniV3;
//    address[] rewardsV2;
//    address[] rewardsV3;
//    uint24[] rewardsV3Fee = fee10000_500;

    // OETH
//    address want = 0x94B17476A93b3262d87B9a326965D1E91f9c13E7;
//    address gauge = 0xd03BE91b1932715709e18021734fcB91BB431715;
//    uint pid = 174;
//    bytes crvToNativePath = crvToNativeUniV3;
//    bytes cvxToNativePath = cvxToNativeUniV3;
//    bytes nativeToDepositPath = "";
//    address[9] depositToWant = [native, native, ETH, want, 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3, want, want];
//    uint[3][4] depositToWantParams = [[0,0,15],[0, 1, 1],[1,0,7]];
//    address unirouter = uniV3;
//    address[] rewardsV2;
//    address[] rewardsV3;
//    uint24[] rewardsV3Fee = fee10000_500;

    // TriCryptoUSDC
    address want = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    address gauge = 0x85D44861D024CB7603Ba906F2Dc9569fC02083F6;
    uint pid = 189;
    bytes crvToNativePath = crvToNativeUniV3;
    bytes cvxToNativePath = cvxToNativeUniV3;
    bytes nativeToDepositPath = "";
    address[9] depositToWant = [native, want, want];
    uint[3][4] depositToWantParams = [[2,0,8]];
    address unirouter = uniV3;
    address[] rewardsV2;
    address[] rewardsV3;
    uint24[] rewardsV3Fee = fee10000_500;

    // wBETH
//    address want = 0xBfAb6FA95E0091ed66058ad493189D2cB29385E6;
//    address gauge = 0x50161102a240b1456d770Dbb55c76d8dc2D160Aa;
//    uint pid = 175;
//    bytes crvToNativePath = crvToNativeUniV3;
//    bytes cvxToNativePath = cvxToNativeUniV3;
//    bytes nativeToDepositPath = "";
//    address[9] depositToWant = [native, native, ETH, want, 0xa2E3356610840701BDf5611a53974510Ae27E2e1, want, want];
//    uint[3][4] depositToWantParams = [[0,0,15],[0, 1, 1],[1,0,7]];
//    address unirouter = uniV3;
//    address[] rewardsV2;
//    address[] rewardsV3;
//    uint24[] rewardsV3Fee = fee10000_500;

    // T/ETH
//    address want = 0xCb08717451aaE9EF950a2524E33B6DCaBA60147B;
//    address gauge = 0x6070fBD4E608ee5391189E7205d70cc4A274c017;
//    uint pid = 67;
//    bytes crvToNativePath = crvToNativeUniV3;
//    bytes cvxToNativePath = cvxToNativeUniV3;
//    bytes nativeToDepositPath = "";
//    address[9] depositToWant = [native, 0x752eBeb79963cf0732E9c0fec72a49FD1DEfAEAC, want];
//    uint[3][4] depositToWantParams = [[0,0,7]];
//    address unirouter = uniV3;
//    address[] rewardsV2;
//    address[] rewardsV3;
//    uint24[] rewardsV3Fee = fee10000_500;

    // tBTC
//    address want = 0xF95AAa7EBB1620e46221B73588502960Ef63dBa0;
//    address gauge = 0x0eC3d1f5d737593ff4aEDB8E22EB33a1886ddB9a;
//    uint pid = 146;
//    bytes crvToNativePath = crvToNativeUniV3;
//    bytes cvxToNativePath = cvxToNativeUniV3;
//    address unirouter = uniV3;
//    bytes nativeToDepositPath = routeToPath(route(native, tbtc), fee3000);
//    address[9] depositToWant = [tbtc, want, want];
//    uint[3][4] depositToWantParams = [[0,0,7]];
//    address[] rewardsV2;
//    address[] rewardsV3;
//    uint24[] rewardsV3Fee = fee10000_500;

    // lvUSD
//    address want = 0xe9123CBC5d1EA65301D417193c40A72Ac8D53501;
//    address gauge = 0xf2cBa59952cc09EB23d6F7baa2C47aB79B9F2945;
//    uint pid = 42069;
//    bytes crvToNativePath = "";
//    bytes cvxToNativePath = "";
//    address unirouter = uniV3;
//    address[] rewardsV2 = [0x73C69d24ad28e2d43D03CBf35F79fE26EBDE1011, usdc, native];
//    address[] rewardsV3 = new address[](0);
//    uint24[] rewardsV3Fee = fee10000_500;

    // eUSD-FraxBP
//    address want = 0xAEda92e6A3B1028edc139A4ae56Ec881f3064D4F;
//    address gauge = 0x8605dc0C339a2e7e85EEA043bD29d42DA2c6D784;
//    uint pid = 156;
//    bytes crvToNativePath = crvToNativeUniV3;
//    bytes cvxToNativePath = cvxToNativeUniV3;
//    address unirouter = uniV3;
//    address[] rewardsV3 = new address[](0);
//    uint24[] rewardsV3Fee = fee3000;

//    bytes nativeToDepositPath = routeToPath(route(native, usdc), fee500);

//    address[9] nativeToWant = [native, want, want];
//    address[9] nativeToFraxBpRoute = [native, triCrypto, usdt, crv3pool, usdc, fraxBp, fraxBpLp, want, want];
    uint[3][4] nativeToFraxBp = [[2, 0, 3], [2, 1, 1], [1, 0, 7], [1, 0, 7]];
//    address[9] nativeTo3PoolRoute = [native, triCrypto, usdt, crv3pool, crv3poolLp, want, want];
//    uint[3][4] nativeTo3Pool = [[2, 0, 3], [2, 0, 8], [1, 0, 7]];
//    address[9] usdcTo3PoolRoute = [usdc, crv3pool, crv3poolLp, want, want];
//    uint[3][4] usdcTo3Pool = [[1, 0, 8], [1, 0, 7]];
//    address[9] usdcToFraxBpRoute = [usdc, fraxBp, fraxBpLp, want, want];
//    uint[3][4] usdcToFraxBp = [[1, 0, 7], [1, 0, 7], [1, 0, 7]];

    StrategyCurveConvex.CurveRoute depositToWantRoute = StrategyCurveConvex.CurveRoute(
        depositToWant, depositToWantParams, 0);
//        usdcToFraxBpRoute, usdcToFraxBp, 0);
//         usdcTo3PoolRoute, usdcTo3Pool, 0);
//         nativeTo3PoolRoute, nativeTo3Pool, 0);
//        nativeToFraxBpRoute, nativeToFraxBp, 0);

    IVault vault;
    StrategyCurveConvex strategy;
    VaultUser user;
    uint256 wantAmount = 50000 ether;

    function setUp() public {
        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        vault = IVault(address(vaultV7));
        strategy = new StrategyCurveConvex();
        user = new VaultUser();

        vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);

        StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
        vault : address(vault),
        unirouter : unirouter,
        keeper : PROD_STRAT.keeper(),
        strategist : address(user),
        beefyFeeRecipient : PROD_STRAT.beefyFeeRecipient(),
        beefyFeeConfig : PROD_STRAT.beefyFeeConfig()
        });
        strategy.initialize(want, gauge, pid, crvToNativePath, cvxToNativePath, nativeToDepositPath, depositToWantRoute, commons);
        console.log("Strategy initialized", IERC20Extended(strategy.want()).symbol(), strategy.pid(), strategy.rewardPool());

        if (nativeToDepositPath.length > 0) {
            console.log("nativeToDeposit", bytesToStr(nativeToDepositPath));
        }

        if (rewardsV2.length > 0) {
            console.log("RewardV2", IERC20Extended(rewardsV2[0]).symbol(), routeToStr(rewardsV2));
            strategy.addRewardV2(uniV2, rewardsV2, 0);
        }
        if (rewardsV3.length > 0) {
            bytes memory path = routeToPath(rewardsV3, rewardsV3Fee);
            console.log("RewardV3", IERC20Extended(rewardsV3[0]).symbol(), bytesToStr(path));
            strategy.addRewardV3(path, 1000);
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

    function test_initWithNoPid() external {
        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        IVault vaultNoPid = IVault(address(vaultV7));
        StrategyCurveConvex strategyNoPid = new StrategyCurveConvex();

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
        strategyNoPid.initialize(want, gauge, strategy.NO_PID(), crvToNativePath, cvxToNativePath, nativeToDepositPath, depositToWantRoute, commons);

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
        console.log("Want as deposit token reverts");
        vm.expectRevert();
        strategy.setDepositToWant([want, a0, a0, a0, a0, a0, a0, a0, a0], nativeToFraxBp, 1e18);

        console.log("Deposit token approved on curve router");
        address token = native;
        strategy.setDepositToWant([token, a0, a0, a0, a0, a0, a0, a0, a0], nativeToFraxBp, 1e18);
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
        strategy.resetCurveRewards();
        strategy.resetRewardsV3();

        console.log("Add curveReward");
        uint[3] memory p = [uint(1),uint(0), uint(0)];
        uint[3][4] memory _params = [p,p,p,p];
        strategy.addReward([crv,a0,a0,a0,a0,a0,a0,a0,a0], _params, 1);
        strategy.addReward([cvx,a0,a0,a0,a0,a0,a0,a0,a0], _params, 1);
        (address[9] memory r, uint256[3][4] memory params, uint minAmount) = strategy.curveReward(0);
        address token0 = r[0];
        assertEq(token0, crv, "!crv");
        assertEq(params[0][0], _params[0][0], "!params");
        assertEq(minAmount, 1, "!minAmount");
        (r,,) = strategy.curveReward(1);
        address token1 = r[0];
        assertEq(token1, cvx, "!cvx");
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
        if (strategy.rewardPool() != address(0)) {
            strategy.booster().earmarkRewards(strategy.pid());
        }

        _depositIntoVault(user, wantAmount);
        skip(1 days);

        // only if convex
        if (strategy.rewardPool() != address(0)) {
            uint rewardsAvailable = strategy.rewardsAvailable();
            assertGt(rewardsAvailable, 0, "Expected rewardsAvailable > 0");
        }

        address[] memory rewards = new address[](strategy.curveRewardsLength() + strategy.rewardsV2Length() + strategy.rewardsV3Length());
        for(uint i; i < strategy.curveRewardsLength(); ++i) {
            (address[9] memory route,,) = strategy.curveReward(i);
            rewards[i] = route[0];
        }
        for(uint i; i < strategy.rewardsV2Length(); ++i) {
            (address router, address[] memory route,) = strategy.rewardV2(i);
            rewards[strategy.curveRewardsLength() + i] = route[0];
            uint out = IUniswapRouterETH(router).getAmountsOut(1e20, route)[route.length - 1];
            console.log("Route 100", IERC20Extended(route[0]).symbol(), "to ETH:", out);
        }
        for(uint i; i < strategy.rewardsV3Length(); ++i) {
            rewards[strategy.curveRewardsLength() + strategy.rewardsV2Length() + i] = strategy.rewardV3Route(i)[0];
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
            deal(cvx, address(strategy), 1e20);
        } else {
            console.log("Claim rewards on Curve");
            IRewardsGauge(strategy.gauge()).claim_rewards(address(strategy));
            if (strategy.isCrvMintable()) {
                minter.mint(strategy.gauge());
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

    function test_earmark() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        // pass periodFinish
        skip(7 days);
        _depositIntoVault(user, wantAmount);
        uint bal = vault.balance();

        uint rewardsAvailable = strategy.rewardsAvailable();
        assertEq(rewardsAvailable, 0, "Expected 0 rewardsAvailable");

        uint periodFinish = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertLt(periodFinish, block.timestamp, "periodFinish not ended");

        console.log("Harvest");
        strategy.harvest();
        assertGt(vault.balance(), bal, "Not Harvested");
        periodFinish = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertGt(periodFinish, block.timestamp, "periodFinish not updated");
    }

    function test_skipEarmark() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;

        // pass periodFinish
        skip(7 days);
        _depositIntoVault(user, wantAmount);
        uint bal = vault.balance();

        uint rewardsAvailable = strategy.rewardsAvailable();
        assertEq(rewardsAvailable, 0, "Expected 0 rewardsAvailable");

        uint periodFinish = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertLt(periodFinish, block.timestamp, "periodFinish not ended");

        console.log("SkipEarmarkRewards");
        strategy.setSkipEarmarkRewards(true);
        console.log("Harvest");
        strategy.harvest();
        assertEq(vault.balance(), bal, "Harvested");
        uint periodFinishNew = IConvexRewardPool(strategy.rewardPool()).periodFinish();
        assertEq(periodFinishNew, periodFinish, "periodFinish updated");
    }
}