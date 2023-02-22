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
import "../../../contracts/BIFI/strategies/Curve/StrategyConvex.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyConvexTest is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0x2486c5fa59Ba480F604D5A99A6DAF3ef8A5b4D76);
    address constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant ldo = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address constant fxs = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant uniV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant zapFraxBp = 0x08780fb7E580e492c1935bEe4fA5920b94AA95Da;
    address constant zap3pool = 0xA79828DF1850E8a3A3064576f380D90aECDD3359;
    uint24[] fee500 = [500];
    uint24[] fee3000 = [3000];
    uint24[] fee10000 = [10000];
    bytes nativeToUsdc = routeToPath(route(native, usdc), fee500);

    // LDO-ETH
    IERC20Like want = IERC20Like(0xb79565c01b7Ae53618d9B847b9443aAf4f9011e7);
    address pool = 0x9409280DC1e6D33AB7A8C6EC03e5763FB61772B5;
    address zap = address(0);
    uint pid = 149;
    uint poolSize = 2;
    uint depositIndex = 0;
    uint useUnderlying = 0;
    uint depositNative = 0;
    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
    address unirouter = uniV3;
    bytes nativeToDepositPath = "";
    address[] nativeToDepositRoute = [native];
    address[] rewardsV3 = new address[](0);
    uint24[] rewardsV3Fee = [3000];

    // CLEV-ETH
//    IERC20Like want = IERC20Like(0x6C280dB098dB673d30d5B34eC04B6387185D3620);
//    address pool = 0x342D1C4Aa76EA6F5E5871b7f11A019a0eB713A4f;
//    address zap = address(0);
//    uint pid = 142;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = uniV3;
//    bytes nativeToDepositPath = "";
//    address[] nativeToDepositRoute = [native];
//    address[] rewardsV3 = new address[](0);
//    uint24[] rewardsV3Fee = [3000];

    // clevCVX
//    IERC20Like want = IERC20Like(0xF9078Fb962A7D13F55d40d49C8AA6472aBD1A5a6);
//    address pool = 0xF9078Fb962A7D13F55d40d49C8AA6472aBD1A5a6;
//    address zap = address(0);
//    uint pid = 139;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = uniV3;
//    uint24[] fee = fee10000;
//    bytes nativeToDepositPath = routeToPath(route(native, cvx), fee);
//    address[] nativeToDepositRoute = new address[](0);
//    address[] rewardsV3 = new address[](0);
//    uint24[] rewardsV3Fee = [3000];

    // yCRV
//    IERC20Like want = IERC20Like(0x453D92C7d4263201C69aACfaf589Ed14202d83a4);
//    address pool = 0x453D92C7d4263201C69aACfaf589Ed14202d83a4;
//    address zap = address(0);
//    uint pid = 124;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = uniV3;
//    uint24[] fee = fee3000;
//    bytes nativeToDepositPath = routeToPath(route(native, crv), fee);
//    address[] nativeToDepositRoute = new address[](0);
//    address[] rewardsV3 = new address[](0);
//    uint24[] rewardsV3Fee = [3000];

    // tusd-3pool
//    IERC20Like want = IERC20Like(0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1);
//    address pool = 0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1;
//    address zap = zap3pool;
//    uint pid = 31;
//    uint poolSize = 4;
//    uint depositIndex = 2;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = uniV3;
//    uint24[] fee = fee500;
//    bytes nativeToDepositPath = routeToPath(route(native, usdc), fee);
//    address[] nativeToDepositRoute = new address[](0);
//    address[] rewardsV3 = new address[](0);
//    uint24[] rewardsV3Fee = [3000];

    // sbtc2
//    IERC20Like want = IERC20Like(0x051d7e5609917Bd9b73f04BAc0DED8Dd46a74301);
//    address pool = 0xf253f83AcA21aAbD2A20553AE0BF7F65C755A07F;
//    address zap = address(0);
//    uint pid = 135;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = uniV3;
//    bytes nativeToDepositPath = routeToPath(route(native, wbtc), fee500);
//    address[] nativeToDepositRoute = new address[](0);
//    address[] rewardsV3 = new address[](0);
//    uint24[] rewardsV3Fee = [3000];

    // multibtc
//    IERC20Like want = IERC20Like(0x2863a328A0B7fC6040f11614FA0728587DB8e353);
//    address pool = 0x2863a328A0B7fC6040f11614FA0728587DB8e353;
//    address zap = 0xA2d40Edbf76C6C0701BA8899e2d059798eBa628e;
//    uint pid = 137;
//    uint poolSize = 3;
//    uint depositIndex = 1;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = uniV3;
//    bytes nativeToDepositPath = routeToPath(route(native, wbtc), fee500);
//    address[] nativeToDepositRoute = new address[](0);
//    address[] rewardsV3 = new address[](0);
//    uint24[] rewardsV3Fee = [3000];

    // cvxFXS
//    IERC20Like want = IERC20Like(0xF3A43307DcAFa93275993862Aae628fCB50dC768);
//    address pool = 0xd658A338613198204DCa1143Ac3F01A722b5d94A;
//    address zap = address(0);
//    uint pid = 72;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = uniV3;
//    bytes nativeToDepositPath = routeToPath(route(native, fxs), fee3000);
//    address[] nativeToDepositRoute = [native];
//    uint24[] rewardsV3Fee = [3000];
//    address[] rewardsV3 = [fxs, native];

    // crvETH
//    IERC20Like want = IERC20Like(0xEd4064f376cB8d68F770FB1Ff088a3d0F3FF5c4d);
//    address pool = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
//    address zap = address(0);
//    uint pid = 61;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
//    bytes nativeToDepositPath = "";
//    address[] nativeToDepositRoute = [native];
//    uint24[] rewardsV3Fee = [3000];
//    address[] rewardsV3 = new address[](0);

    // cvxETH
//    IERC20Like want = IERC20Like(0x3A283D9c08E8b55966afb64C515f5143cf907611);
//    address pool = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;
//    address zap = address(0);
//    uint pid = 64;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
//    bytes nativeToDepositPath = "";
//    address[] nativeToDepositRoute = [native];
//    uint24[] rewardsV3Fee = [3000];
//    address[] rewardsV3 = new address[](0);
    // address[] rewardsV3 = [ldo, native];

    // frxETH
//    IERC20Like want = IERC20Like(0xf43211935C781D5ca1a41d2041F397B8A7366C7A);
//    address pool = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
//    address zap = address(0);
//    uint pid = 128;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 1;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
//    bytes nativeToDepositPath = "";
//    address[] nativeToDepositRoute = [native];
//    uint24[] rewardsV3Fee = [3000];
//    address[] rewardsV3 = new address[](0);
//    // address[] rewardsV3 = [ldo, native];

    // sETH
//    IERC20Like want = IERC20Like(0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c);
//    address pool = 0xc5424B857f758E906013F3555Dad202e4bdB4567;
//    address zap = address(0);
//    uint pid = 23;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 1;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
//    bytes nativeToDepositPath = "";
//    address[] nativeToDepositRoute = [native];
//    uint24[] rewardsV3Fee = [3000];
//    address[] rewardsV3 = new address[](0);
//    // address[] rewardsV3 = [ldo, native];

    // cbETH
//    IERC20Like want = IERC20Like(0x5b6C539b224014A09B3388e51CaAA8e354c959C8);
//    address pool = 0x5FAE7E604FC3e24fd43A72867ceBaC94c65b404A;
//    address zap = address(0);
//    uint pid = 127;
//    uint poolSize = 2;
//    uint depositIndex = 0;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
//    bytes nativeToDepositPath = "";
//    address[] nativeToDepositRoute = [native];
//    uint24[] rewardsV3Fee = [3000];
//    address[] rewardsV3 = new address[](0);
//    // address[] rewardsV3 = [ldo, native];

//     usdd-3pool
//    IERC20Like want = IERC20Like(0xe6b5CC1B4b47305c58392CE3D359B10282FC36Ea);
//    address pool = 0xe6b5CC1B4b47305c58392CE3D359B10282FC36Ea;
//    address zap = zap3pool;
//    uint pid = 96;
//    uint poolSize = 4;
//    uint depositIndex = 2;
//    uint useUnderlying = 0;
//    uint depositNative = 0;
//    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
//    address unirouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
//    uint24[] fee = [500];
//    bytes nativeToDepositPath = routeToPath(route(native, usdc), fee);
//    address[] nativeToDepositRoute = new address[](0);
//    address[] rewardsV3 = new address[](0);
////    address[] rewardsV3 = [ldo, native];
//    uint24[] rewardsV3Fee = [3000];

    IVault vault;
    StrategyConvex strategy;
    VaultUser user;
    uint256 wantAmount = 50000 ether;

    function setUp() public {
        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        vault = IVault(address(vaultV7));
        strategy = new StrategyConvex();
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
        strategy.initialize(address(want), pool, zap, pid, params, nativeToDepositPath, nativeToDepositRoute, commons);
        console.log("Strategy initialized", strategy.pid(), strategy.want(), strategy.rewardPool());

        if (nativeToDepositPath.length > 0) {
            console.log("nativeToDeposit", bytesToStr(nativeToDepositPath));
        }
        if (rewardsV3.length > 0) {
            console.log("Add rewardV3", rewardsV3[0]);
            bytes memory path = routeToPath(rewardsV3, rewardsV3Fee);
            strategy.addRewardV3(path, 1000);
        }
        strategy.setCurveSwapMinAmount(1);

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

    function test_addRewards() external {
        strategy.resetRewardsV2();
        strategy.resetRewardsV3();

        console.log("Add rewardV2");
        strategy.addRewardV2(address(this), route(strategy.crv(), strategy.native()), 1);
        strategy.addRewardV2(address(this), route(strategy.cvx(), strategy.native()), 1);
        (address token0, address router, uint minAmount) = strategy.rewards(0);
        assertEq(token0, strategy.crv(), "!crv");
        assertEq(router, address(this), "!router");
        assertEq(minAmount, 1, "!minAmount");
        (address token1,,) = strategy.rewards(1);
        assertEq(token1, strategy.cvx(), "!cvx");
        vm.expectRevert();
        strategy.rewards(2);

        console.log("Add rewardV3");
        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;
        strategy.addRewardV3(routeToPath(route(strategy.crv(), strategy.native()), fees), 1);
        bytes memory b;
        (token0, b, minAmount) = strategy.rewardsV3(0);
        assertEq(token0, strategy.crv(), "!crv");
        assertEq(minAmount, 1, "!minAmount");
        vm.expectRevert();
        strategy.rewardsV3(1);


        console.log("rewardV3ToNative");
        print(strategy.rewardV3ToNative());
        console.log("rewardToNative");
        print(strategy.rewardToNative());
        console.log("nativeToDeposit");
        print(strategy.nativeToDeposit());

        strategy.resetRewardsV2();
        strategy.resetRewardsV3();
        vm.expectRevert();
        strategy.rewards(0);
        vm.expectRevert();
        strategy.rewardsV3(0);
    }

    function test_rewards() external {
        _depositIntoVault(user, wantAmount);
        skip(1 days);

        uint rewardsAvailable = strategy.rewardsAvailable();
        assertGt(rewardsAvailable, 0, "Expected rewardsAvailable > 0");

        address[] memory rewards = new address[](strategy.rewardsLength() + strategy.rewardsV3Length());
        for(uint i; i < strategy.rewardsLength(); ++i) {
            rewards[i] = strategy.rewardToNative(i)[0];
        }
        for(uint i; i < strategy.rewardsV3Length(); ++i) {
            rewards[strategy.rewardsLength() + i] = strategy.rewardV3ToNative(i)[0];
        }

        console.log("Claim rewards on Convex");
        IConvexRewardPool(strategy.rewardPool()).getReward(address(strategy), true);
        uint crvBal = IERC20(strategy.crv()).balanceOf(address(strategy));
        uint cvxBal = IERC20(strategy.cvx()).balanceOf(address(strategy));
        uint nativeBal = IERC20(native).balanceOf(address(strategy));
        console.log("CRV", crvBal);
        console.log("CVX", cvxBal);
        for (uint i; i < rewards.length; ++i) {
            console2.log(rewards[i], IERC20(rewards[i]).balanceOf(address(strategy)));
        }
        console.log("WETH", nativeBal);
        deal(strategy.crv(), address(strategy), 1e20);
        deal(strategy.cvx(), address(strategy), 1e20);

        console.log("Harvest");
        strategy.harvest();
        crvBal = IERC20(strategy.crv()).balanceOf(address(strategy));
        cvxBal = IERC20(strategy.cvx()).balanceOf(address(strategy));
        nativeBal = IERC20(native).balanceOf(address(strategy));
        console.log("CRV", crvBal);
        console.log("CVX", cvxBal);
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i]).balanceOf(address(strategy));
            console2.log(rewards[i], bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
        console.log("WETH", nativeBal);
        assertEq(crvBal, 0, "CRV not swapped");
        assertEq(crvBal, 0, "CVX not swapped");
        assertEq(nativeBal, 0, "Native not swapped");
    }

    function test_earmark() external {
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

    function test_skipCurveSwap() external {
        strategy.resetRewardsV2();
        strategy.resetRewardsV3();
        strategy.setCurveSwapMinAmount(0);

        _depositIntoVault(user, wantAmount);
        uint bal = vault.balance();
        skip(1 days);

        console.log("Harvest");
        strategy.harvest();
        assertEq(vault.balance(), bal, "Expectted Harvested 0");
    }
}