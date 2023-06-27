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
import "../../../contracts/BIFI/strategies/Curve/StrategyConic.sol";
import "../../../contracts/BIFI/strategies/Curve/ConicZap.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/utils/UniswapV3Utils.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyConicTest is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0x2486c5fa59Ba480F604D5A99A6DAF3ef8A5b4D76);
    address constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant triCryptoUSDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    address constant crvUSD_USDC = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address constant crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address constant uniV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant uniV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address a0 = address(0);
    uint24[] fee500 = [500];
    uint24[] fee3000 = [3000];
    uint24[] fee10000 = [10000];
    uint24[] fee10000_500 = [10000, 500];

    bytes crvToNativePath = routeToPath(route(crv, native), fee3000);
    bytes cvxToNativePath = routeToPath(route(cvx, native), fee10000);
    address unirouter = uniV3;

    // crvUSD
    address want = 0xB569bD86ba2429fd2D8D288b40f17EBe1d0f478f;
    bytes nativeToUnderlyingPath = "";
    address[9] nativeToUnderlying = [native, triCryptoUSDC, usdc, crvUSD_USDC, crvUSD];
    uint[3][4] nativeToUnderlyingParams = [[2,0,3],[0, 1, 1]];
    StrategyConic.CurveRoute nativeToUnderlyingRoute = StrategyConic.CurveRoute(nativeToUnderlying, nativeToUnderlyingParams, 0);

    // USDC pool
//    address want = 0x472fCC880F01B32C55F1fB55F58f7bD930dE1944;
//    bytes nativeToUnderlyingPath = routeToPath(route(native, usdc), fee500);
//    address[9] nativeToUnderlying = [native, triCryptoUSDC, usdc];
//    uint[3][4] nativeToUnderlyingParams = [[2,0,3]];
//    StrategyConic.CurveRoute nativeToUnderlyingRoute = StrategyConic.CurveRoute(nativeToUnderlying, nativeToUnderlyingParams, 0);

    address[] rewardsV3;
    uint24[] rewardsV3Fee = fee10000_500;
    uint[3][4] nativeToFraxBp = [[2, 0, 3], [2, 1, 1], [1, 0, 7], [1, 0, 7]];

    IVault vault;
    StrategyConic strategy;
    VaultUser user;
    uint256 wantAmount = 500000 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyConic(payable(vault.strategy()));
            console.log("Testing vault at", vaultAddress);
            console.log(vault.name(), vault.symbol());
        } else {
            BeefyVaultV7 vaultV7 = new BeefyVaultV7();
            vault = IVault(address(vaultV7));
            strategy = new StrategyConic();

            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);

            StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
                vault: address(vault),
                unirouter: unirouter,
                keeper: PROD_STRAT.keeper(),
                strategist: address(user),
                beefyFeeRecipient: PROD_STRAT.beefyFeeRecipient(),
                beefyFeeConfig: PROD_STRAT.beefyFeeConfig()
            });
            strategy.initialize(want, crvToNativePath, cvxToNativePath, nativeToUnderlyingPath, nativeToUnderlyingRoute, commons);
            console.log("Strategy initialized", IERC20Extended(strategy.want()).symbol(), strategy.conicPool());

            if (nativeToUnderlyingPath.length > 0) {
                console.log("nativeToUnderlyingPath", bytesToStr(nativeToUnderlyingPath));
            }
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

    function test_zapIn() external {
        ConicZap zap = new ConicZap();
        IBeefyVault beefyVault = IBeefyVault(address(vault));

        vm.expectRevert('Beefy: Input token not present in pool');
        zap.estimateSwap(beefyVault, cvx, 1000);

        address tokenIn = strategy.underlying();
        uint amount = 1000000000;
        (uint swapAmountIn, uint swapAmountOut, address swapTokenOut) = zap.estimateSwap(beefyVault, tokenIn, amount);
        uint amountMin = swapAmountOut * 999 / 1000; // 0.1%
        console.log('Estimate swap', swapAmountIn, swapAmountOut, amountMin);
        assertEq(swapAmountIn, amount, "swapAmountIn != amount");
        assertLt(swapAmountOut, swapAmountIn, "swapAmountOut >= swapAmountIn");
        assertEq(swapTokenOut, want, "swapTokenOut != want");

        deal(tokenIn, address(this), amount);
        IERC20(tokenIn).approve(address(zap), type(uint).max);
        zap.beefIn(beefyVault, amountMin, tokenIn, amount);

        assertEq(IERC20(strategy.cnc()).balanceOf(address(zap)), 0);
        assertEq(IERC20(strategy.underlying()).balanceOf(address(zap)), 0);
        assertEq(IERC20(want).balanceOf(address(zap)), 0);

        uint mooBal = beefyVault.balanceOf(address(this));
        uint tokenBal = mooBal * beefyVault.balance() / beefyVault.totalSupply();
        assertGe(tokenBal, amountMin, "Balance < amountMin");
    }

    function test_zapOut() external {
        ConicZap zap = new ConicZap();
        IBeefyVault beefyVault = IBeefyVault(address(vault));

        vm.expectRevert('Beefy: desired token not present in pool');
        zap.estimateSwapOut(beefyVault, cvx, 1000);

        uint lpAmount = 10000;
        deal(want, address(this), lpAmount);
        IERC20(want).approve(address(vault), lpAmount);
        vault.deposit(lpAmount);
        uint withdrawAmount = beefyVault.balanceOf(address(this));

        address tokenOut = strategy.underlying();
        (uint swapAmountIn, uint swapAmountOut, address swapTokenIn) = zap.estimateSwapOut(beefyVault, tokenOut, withdrawAmount);
        uint amountMin = swapAmountOut * 999 / 1000; // 0.1%
        console.log('Estimate swapOut', swapAmountIn, swapAmountOut, amountMin);
        uint withdrawAmountAfterFee = withdrawAmount - (withdrawAmount * strategy.withdrawFee() / strategy.WITHDRAWAL_MAX());
        assertEq(swapAmountIn, withdrawAmountAfterFee, "swapAmountIn != amount");
        assertGt(swapAmountOut, swapAmountIn, "swapAmountOut < swapAmountIn");
        assertEq(swapTokenIn, want, "swapTokenIn != want");

        beefyVault.approve(address(zap), type(uint).max);
        zap.beefOutAndSwap(beefyVault, withdrawAmount, tokenOut, amountMin);

        assertEq(IERC20(strategy.cnc()).balanceOf(address(zap)), 0);
        assertEq(IERC20(strategy.underlying()).balanceOf(address(zap)), 0);
        assertEq(IERC20(want).balanceOf(address(zap)), 0);

        uint tokenBal = IERC20(tokenOut).balanceOf(address(this));
        assertGe(tokenBal, amountMin, "Balance < amountMin");
    }

    function test_setNativeToUnderlyingPath() external {
        console.log("Non-native path reverts");
        vm.expectRevert();
        strategy.setNativeToUnderlyingPath(routeToPath(route(usdc, native), fee3000));
    }

    function test_setNativeToUnderlying() external {
        console.log("Want as deposit token reverts");
        vm.expectRevert();
        strategy.setNativeToUnderlyingRoute([want, a0, a0, a0, a0, a0, a0, a0, a0], nativeToFraxBp, 1e18);

        console.log("Non-native as deposit token reverts");
        vm.expectRevert();
        strategy.setNativeToUnderlyingRoute([usdc, a0, a0, a0, a0, a0, a0, a0, a0], nativeToFraxBp, 1e18);

        console.log("Deposit token approved on curve router");
        address token = native;
        vm.prank(strategy.owner());
        strategy.setNativeToUnderlyingRoute([token, a0, a0, a0, a0, a0, a0, a0, a0], nativeToFraxBp, 1e18);
        uint allowed = IERC20(token).allowance(address(strategy), strategy.curveRouter());
        assertEq(allowed, type(uint).max);
    }

    function test_addRewards() external {
        vm.prank(strategy.owner());
        strategy.resetCurveRewards();
        vm.prank(strategy.owner());
        strategy.resetRewardsV3();

        console.log("Add curveReward");
        uint[3] memory p = [uint(1),uint(0), uint(0)];
        uint[3][4] memory _params = [p,p,p,p];
        vm.prank(strategy.owner());
        strategy.addReward([crv,a0,a0,a0,a0,a0,a0,a0,a0], _params, 1);
        vm.prank(strategy.owner());
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
        bytes memory path = routeToPath(route(crv, strategy.native()), fees);
        vm.prank(strategy.owner());
        strategy.addRewardV3(path, 1);
        (token0,,minAmount) = strategy.rewardsV3(0);
        assertEq(token0, crv, "!crv");
        assertEq(minAmount, 1, "!minAmount");
        vm.expectRevert();
        strategy.rewardsV3(1);


        console.log("rewardV3Route");
        print(strategy.rewardV3Route(0));
        console.log("nativeToUnderlying");
        path = strategy.nativeToUnderlyingPath();
        if (path.length > 0) {
            print(UniswapV3Utils.pathToRoute(path));
        }
        console.log("nativeToUnderlyingRoute");
        (r, params, minAmount) = strategy.nativeToUnderlyingRoute();
        for(uint i; i < r.length; i++) {
            if (r[i] == address(0)) break;
            console.log(r[i]);
        }

        vm.prank(strategy.owner());
        strategy.resetCurveRewards();
        vm.prank(strategy.owner());
        strategy.resetRewardsV3();

        vm.expectRevert();
        strategy.rewardsV3(0);

        vm.expectRevert();
        strategy.curveRewards(0);
    }

    function test_rewards() external {
        _depositIntoVault(user, wantAmount);
        skip(1 days);

        uint rewardsAvailable = strategy.rewardsAvailable();
        assertGt(rewardsAvailable, 0, "Expected rewardsAvailable > 0");

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

        console.log("Claim rewards");
        IRewardManager rewardManager = strategy.rewardManager();
        vm.prank(address(strategy));
        rewardManager.claimEarnings();
        for (uint i; i < rewards.length; ++i) {
            string memory s = IERC20Extended(rewards[i]).symbol();
            console2.log(s, IERC20(rewards[i]).balanceOf(address(strategy)));
        }
        console.log("WETH", IERC20(native).balanceOf(address(strategy)));

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

}