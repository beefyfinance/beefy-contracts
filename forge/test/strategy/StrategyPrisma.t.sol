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
import "../../../contracts/BIFI/strategies/Curve/StrategyPrisma.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/utils/UniswapV3Utils.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyPrismaTest is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0x2486c5fa59Ba480F604D5A99A6DAF3ef8A5b4D76);
    address public native = PROD_STRAT.native();
    address constant curveRouter = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant prisma = 0xdA47862a83dac0c112BA89c6abC2159b95afd71C;
    address constant prismaEthPool = 0x322135Dd9cBAE8Afa84727d9aE1434b5B3EBA44B;
    address constant cvxPrisma = 0x34635280737b5BFe6c7DC2FC3065D60d66e78185;
    address constant cvxPrismaPool = 0x3b21C2868B6028CfB38Ff86127eF22E68d16d53B;
    address constant triCRV = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;
    address constant crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address constant mkUSD = 0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28;
    address constant mkUSDEthPool = 0xc89570207c5BA1B0E3cD372172cCaEFB173DB270;

    address constant uniV3 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant uniV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    uint constant minAmountToSwap = 1e17;
    address a0 = address(0);
    uint24[] fee500 = [500];
    uint24[] fee3000 = [3000];
    uint24[] fee10000 = [10000];
    uint24[] fee10000_500 = [10000, 500];

    // mkUSD-FraxBP
    address want = 0x0CFe5C777A7438C9Dd8Add53ed671cEc7A5FAeE5;
    address rewardPool = 0x0Ae09f649e9dA1b6aEA0c10527aC4e8a88a37480;
    address newRewardPool = 0x5F8D4319C27a940B5783b4495cCa6626E880532E;
    address[11] depositToWant = [native, mkUSDEthPool, mkUSD, want, want];
    uint[5][5] depositToWantParams = [[0, 1, 1, 2, 2], [0, 0, 4, 1, 2]];

    // mkUSD-crvUSD
//    address want = 0x3de254A0f838a844F727fee81040e0FA7884B935;
//    address rewardPool = 0x71aD6c1d92546065B13bf701a7524c69B409E25C;
//    address newRewardPool = 0xf6aA46869220Ae703924d5331D88A21DceF3b19d;
//    address[11] depositToWant = [native, triCRV, crvUSD, want, want];
//    uint[5][5] depositToWantParams = [[1, 0, 1, 3, 4], [1, 0, 4, 1, 2]];

    // ETH-PRISMA
//    address want = 0xb34e1a3D07f9D180Bc2FDb9Fd90B8994423e33c1;
//    address rewardPool = 0xB5376AB455194328Fe41450a587f11bcDA2363fa;
//    address newRewardPool = 0x685E852E4c18c2c554a1D25c1197684fd9593145;
//    address[11] depositToWant = [native, prismaEthPool, want];
//    uint[5][5] depositToWantParams = [[0, 0, 4, 2, 2]];

    CurveRoute depositToWantRoute = CurveRoute(depositToWant, depositToWantParams, 0);
    bytes crvToNativeUniV3 = routeToPath(route(crv, native), fee3000);
    bytes cvxToNativeUniV3 = routeToPath(route(cvx, native), fee10000);
    bytes[] rewardsV3 = [crvToNativeUniV3, cvxToNativeUniV3];
    address unirouter = uniV3;

    address[11] cvxPrismaToNative = [cvxPrisma, cvxPrismaPool, prisma, prismaEthPool, native];
    uint[5][5] cvxPrismaParams = [[1, 0, 1, 1, 2], [1, 0, 1, 2, 2]];
    function rewardsToNative() internal view returns (CurveRoute[] memory rewards) {
        rewards = new CurveRoute[](1);
        rewards[0] = CurveRoute(cvxPrismaToNative, cvxPrismaParams, 0);
    }

    IVault vault;
    StrategyPrisma strategy;
    VaultUser user;
    uint256 wantAmount = 50000 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyPrisma(vault.strategy());
            console.log("Testing vault at", vaultAddress);
            console.log(vault.name(), vault.symbol());
        } else {
            BeefyVaultV7 vaultV7 = new BeefyVaultV7();
            vault = IVault(address(vaultV7));
            strategy = new StrategyPrisma();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
                vault: address(vault),
                unirouter: unirouter,
                keeper: PROD_STRAT.keeper(),
                strategist: address(user),
                beefyFeeRecipient: PROD_STRAT.beefyFeeRecipient(),
                beefyFeeConfig: PROD_STRAT.beefyFeeConfig()
            });
            strategy.initialize(want, rewardPool, rewardsV3, rewardsToNative(), depositToWantRoute, commons);
            console.log("Strategy initialized", IERC20Extended(strategy.want()).symbol(), strategy.rewardPool());
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

    function test_setPrismaRewardPool() external {
        if (newRewardPool == address(0)) return;
        _depositIntoVault(user, wantAmount);

        address oldRewardPool = strategy.rewardPool();
        uint rewardPoolBal = IPrismaRewardPool(oldRewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");

        console.log("Switch to new reward pool");
        vm.prank(strategy.owner());
        strategy.setPrismaRewardPool(newRewardPool);
        rewardPoolBal = IPrismaRewardPool(oldRewardPool).balanceOf(address(strategy));
        assertEq(rewardPoolBal, 0, "Old rewardPool balance != 0");
        uint gaugeBal = IPrismaRewardPool(newRewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), gaugeBal, "New rewardPool balance != vault balance");
        user.withdrawAll(vault);
        uint userBal = IERC20(want).balanceOf(address(user));
        assertLe(userBal, wantAmount, "Expected userBal <= wantAmount");
        assertGt(userBal, wantAmount * 99 / 100, "Expected userBal > wantAmount * 99 / 100");

        _depositIntoVault(user, userBal);
        console.log("setPrismaRewardPool bad pool reverts");
        address badPool = strategy.want();
        vm.prank(strategy.owner());
        vm.expectRevert();
        strategy.setPrismaRewardPool(badPool);

        console.log("Switch back to old reward pool");
        vm.prank(strategy.owner());
        strategy.setPrismaRewardPool(oldRewardPool);
        rewardPoolBal = IPrismaRewardPool(oldRewardPool).balanceOf(address(strategy));
        assertEq(vault.balance(), rewardPoolBal, "RewardPool balance != vault balance");
        gaugeBal = IPrismaRewardPool(newRewardPool).balanceOf(address(strategy));
        assertEq(gaugeBal, 0, "New rewardPool balance != 0");
        user.withdrawAll(vault);
        uint userBalFinal = IERC20(want).balanceOf(address(user));
        assertLe(userBalFinal, userBal, "Expected userBalFinal <= userBal");
        assertGt(userBalFinal, userBal * 99 / 100, "Expected userBalFinal > userBal * 99 / 100");
    }

    function test_setBoostDelegate() external {
        address receiver = strategy.want();
        address delegate = strategy.rewardPool();
        uint maxFee = 777;
        vm.prank(strategy.keeper());
        strategy.setBoostDelegate(receiver, delegate, maxFee);
        assertEq(strategy.prismaReceiver(), receiver, "Wrong prismaReceiver");
        assertEq(strategy.boostDelegate(), delegate, "Wrong boostDelegate");
        assertEq(strategy.maxFeePct(), maxFee, "Wrong maxFeePct");
    }

    function test_canHarvest() external {
        assertTrue(strategy.canHarvest(), "canHarvest is false initially");

        _depositIntoVault(user, wantAmount);
        skip(1 hours);
        strategy.harvest();
        assertGt(strategy.lastHarvest(), 0, "Not harvested");
        skip(1 hours);

        uint pending = strategy.rewardsAvailable();
        assertGt(pending, 0, "No pending rewards");
        vm.mockCall(
            address(strategy.prismaVault()),
            abi.encodeWithSelector(IPrismaVault.getClaimableWithBoost.selector, strategy.boostDelegate()),
            abi.encode(pending - 1, 0)
        );
        (uint maxBoosted,) = strategy.prismaVault().getClaimableWithBoost(strategy.boostDelegate());
        assertLt(maxBoosted, pending, "maxBoosted greater than pending");
        assertFalse(strategy.canHarvest(), "canHarvest is true without max boost");

        address delegate = strategy.boostDelegate();
        vm.prank(strategy.keeper());
        strategy.setBoostDelegate(address(strategy), address(0), 10000);
        assertTrue(strategy.canHarvest(), "canHarvest is false with empty delegate");

        // reset
        vm.prank(strategy.keeper());
        strategy.setBoostDelegate(delegate, delegate, 10000);
        assertFalse(strategy.canHarvest(), "canHarvest is true when not max boost");

        skip(7 days);
        assertTrue(strategy.canHarvest(), "canHarvest is false in new epoch");
    }

    function test_setNativeToDepositPath() external {
        console.log("Non-native path reverts");
        vm.expectRevert();
        strategy.setNativeToDepositPath(routeToPath(route(prisma, native), fee3000));
    }

    function test_setDepositToWant() external {
        vm.startPrank(strategy.keeper());
        address[11] memory r;
        uint[5][5] memory p;
        console.log("Want as deposit token reverts");
        r[0] = strategy.want();
        vm.expectRevert();
        strategy.setDepositToWant(r, p, 1e18);

        console.log("Deposit token approved on curve router");
        address token = native;
        r[0] = token;
        strategy.setDepositToWant(r, p, 1e18);
        uint allowed = IERC20(token).allowance(address(strategy), strategy.curveRouter());
        assertEq(allowed, type(uint).max);
    }

    function test_addRewards() external {
        vm.startPrank(strategy.keeper());
        strategy.resetCurveRewards();
        strategy.resetRewardsV3();

        console.log("Add curveReward");
        uint[5] memory p = [uint(1),uint(0), uint(0), uint(0), uint(0)];
        uint[5][5] memory _params = [p,p,p,p,p];
        strategy.addReward([crv,a0,a0,a0,a0,a0,a0,a0,a0,a0,a0], _params, 1);
        (address[11] memory r, uint256[5][5] memory params, uint minAmount) = strategy.curveReward(0);
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
        skip(10 days);

        uint rewardsAvailable = strategy.rewardsAvailable();
        assertGt(rewardsAvailable, 0, "Expected rewardsAvailable > 0");

        address[] memory rewards = new address[](strategy.curveRewardsLength() + strategy.rewardsV3Length());
        for(uint i; i < strategy.curveRewardsLength(); ++i) {
            (address[11] memory route,,) = strategy.curveReward(i);
            rewards[i] = route[0];
        }
        for(uint i; i < strategy.rewardsV3Length(); ++i) {
            rewards[strategy.curveRewardsLength() + i] = strategy.rewardV3Route(i)[0];
            (address token, bytes memory path,) = strategy.rewardsV3(i);
            uint out = IUniV3Quoter(uniV3Quoter).quoteExactInput(path, 1e20);
            console.log("Route 100", IERC20Extended(token).symbol(), "to ETH:", out);
        }

        console.log("Harvest");
        strategy.harvest();
        for (uint i; i < rewards.length; ++i) {
            string memory s = IERC20Extended(rewards[i]).symbol();
            uint bal = IERC20(rewards[i]).balanceOf(address(strategy));
            console2.log(s, bal);
            if (bal > minAmountToSwap) {
                assertEq(bal, 0, "Extra reward not swapped");
            }
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
        console.log(string.concat('rewardPool: "', addrToStr(rewardPool), '",'));

        string memory _rewardsV3 = '[';
        for (uint i; i < rewardsV3.length; i++) {
            _rewardsV3 = string.concat(_rewardsV3, '"', bytesToStr(rewardsV3[i]), '"');
            if (i != rewardsV3.length - 1) {
                _rewardsV3 = string.concat(_rewardsV3, ',');
            }
        }
        _rewardsV3 = string.concat(_rewardsV3, '],');
        console.log('rewardsV3:', _rewardsV3);

        string memory rewards = '[';
        CurveRoute[] memory r = rewardsToNative();
        for (uint i; i < r.length; i++) {
            rewards = string.concat(rewards, curveRouteToStr(r[i]));
            if (i != r.length - 1) {
                rewards = string.concat(rewards, ',');
            }
        }
        rewards = string.concat(rewards, '],');
        console.log('rewardsToNative:', rewards);
        console.log('depositToWant:', string.concat(curveRouteToStr(depositToWantRoute), ','));
    }

    function curveRouteToStr(CurveRoute memory a) public pure returns (string memory t) {
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