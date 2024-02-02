// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/IUniV3Quoter.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyCurveConvex.sol";
import "../../../contracts/BIFI/utils/UniswapV3Utils.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCurveConvexTest is BaseStrategyTest {

    address constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant uniV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    ICrvMinter constant minter = ICrvMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);
    uint24[] fee = [3000];
    uint[3][4] testParams = [[2, 0, 3], [2, 1, 1], [1, 0, 7], [1, 0, 7]];

    StrategyCurveConvex strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyCurveConvex();
        else strategy = StrategyCurveConvex(payable(_impl));
        return address(strategy);
    }

    function test_initWithNoPid() external {
        BeefyVaultV7 vaultV7 = new BeefyVaultV7();
        IVault vaultNoPid = IVault(address(vaultV7));
        StrategyCurveConvex strategyNoPid = new StrategyCurveConvex();

        vaultV7.initialize(IStrategyV7(address(strategyNoPid)), "TestVault", "testVault", 0);
        StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
            vault : address(vaultNoPid),
            unirouter : strategy.unirouter(),
            keeper : strategy.keeper(),
            strategist : address(user),
            beefyFeeRecipient : strategy.beefyFeeRecipient(),
            beefyFeeConfig : address(strategy.beefyFeeConfig())
        });
        console.log("Init Strategy NO_PID");
        (address[9] memory route, uint256[3][4] memory params, uint minAmount) = strategy.depositToWantRoute();
        StrategyCurveConvex.CurveRoute memory depositToWantRoute = StrategyCurveConvex.CurveRoute(
            route, params, minAmount
        );
        (,bytes memory crvPath,) = strategy.rewardsV3(0);
        (,bytes memory cvxPath,) = strategy.rewardsV3(1);
        strategyNoPid.initialize(strategy.want(), strategy.gauge(), strategy.NO_PID(), crvPath, cvxPath, strategy.nativeToDepositPath(), depositToWantRoute, commons);

        user.approve(address(want), address(vaultNoPid), wantAmount);
        user.depositAll(vaultNoPid);
        user.withdrawAll(vaultNoPid);
        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, wantAmount, "Expected wantBalanceFinal <= wantAmount");
        assertGt(wantBalanceFinal, wantAmount * 99 / 100, "Expected wantBalanceFinal > wantAmount * 99 / 100");
    }

    function test_setConvexPid() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;
        uint pid = strategy.pid();

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
        uint userBal = want.balanceOf(address(user));
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
        uint userBalFinal = want.balanceOf(address(user));
        assertLe(userBalFinal, userBal, "Expected userBalFinal <= userBal");
        assertGt(userBalFinal, userBal * 99 / 100, "Expected userBalFinal > userBal * 99 / 100");
    }

    function test_setNativeToDepositPath() external {
        console.log("Non-native path reverts");
        vm.expectRevert();
        strategy.setNativeToDepositPath(routeToPath(route(usdc, native), fee));
    }

    function test_setDepositToWant() external {
        console.log("Want as deposit token reverts");
        vm.expectRevert();
        strategy.setDepositToWant([address(want), a0, a0, a0, a0, a0, a0, a0, a0], testParams, 1e18);

        console.log("Deposit token approved on curve router");
        address token = native;
        strategy.setDepositToWant([token, a0, a0, a0, a0, a0, a0, a0, a0], testParams, 1e18);
        uint allowed = IERC20(token).allowance(address(strategy), strategy.curveRouter());
        assertEq(allowed, type(uint).max);
    }

    function test_setCrvMintable() external {
        // only if convex
        if (strategy.rewardPool() == address(0)) return;
        if (strategy.rewardsV3Length() > 2) return;

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
            for (uint i; i < rewards.length; ++i) {
                string memory s = IERC20Extended(rewards[i]).symbol();
                console2.log(s, IERC20(rewards[i]).balanceOf(address(strategy)));
            }
            if (strategy.isCrvMintable()) {
                console.log("Mint CRV");
                uint balBefore = IERC20(crv).balanceOf(address(strategy));
                vm.startPrank(address(strategy));
                minter.mint(strategy.gauge());
                vm.stopPrank();
                console2.log("CRV minted", IERC20(crv).balanceOf(address(strategy)) - balBefore);
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