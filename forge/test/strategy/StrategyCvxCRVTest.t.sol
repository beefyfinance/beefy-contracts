// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyConvexCRV.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyCvxCRVTest is BaseStrategyTest {

    address constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint24[] fee3000 = [3000];
    address uniV3Reward = usdc;
    bytes uniV3RewardPath = routeToPath(route(uniV3Reward, native), fee3000);

    StrategyConvexCRV strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyConvexCRV();
        else strategy = StrategyConvexCRV(payable(_impl));
        return address(strategy);
    }

    function test_addRewards() external {
        strategy.resetRewards();
        strategy.resetRewardsV3();

        console.log("Add reward");
        address[9] memory _route;
        _route[0] = strategy.crv();
        uint[3][4] memory _params;
        _params[0][0] = 11;
        strategy.addReward(_route, _params, 1);
        _route[0] = strategy.cvx();
        strategy.addReward(_route, _params, 1);
        address[] memory rewardRoute = strategy.rewardToNative(0);
        uint[3][4] memory swapParams = strategy.rewardToNativeParams(0);
        uint minAmount = strategy.rewards(0);
        assertEq(rewardRoute[0], strategy.crv(), "!crv");
        assertEq(swapParams[0][0], 11, "!params");
        assertEq(minAmount, 1, "!minAmount");
        rewardRoute = strategy.rewardToNative(1);
        assertEq(rewardRoute[0], strategy.cvx(), "!cvx");
        vm.expectRevert();
        strategy.rewards(2);

        console.log("Add rewardV3");
        uint24[] memory fees = new uint24[](1);
        fees[0] = 3000;
        strategy.addRewardV3(routeToPath(route(strategy.crv(), strategy.native()), fees), 1);
        address token0;
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
        console.log("nativeToWant");
        print(strategy.nativeToWant());

        strategy.resetRewards();
        strategy.resetRewardsV3();
        vm.expectRevert();
        strategy.rewards(0);
        vm.expectRevert();
        strategy.rewardsV3(0);
    }

    function test_rewards() external {
        _depositIntoVault(user, wantAmount);
        skip(1 days);

        address[] memory rewards = new address[](strategy.rewardsLength() + strategy.rewardsV3Length());
        for(uint i; i < strategy.rewardsLength(); ++i) {
            rewards[i] = strategy.rewardToNative(i)[0];
        }
        for(uint i; i < strategy.rewardsV3Length(); ++i) {
            rewards[strategy.rewardsLength() + i] = strategy.rewardV3ToNative(i)[0];
        }

        console.log("Claim rewards on Convex");
        strategy.stakedCvxCrv().getReward(address(strategy));
        uint crvBal = IERC20(strategy.crv()).balanceOf(address(strategy));
        uint cvxBal = IERC20(strategy.cvx()).balanceOf(address(strategy));
        uint nativeBal = IERC20(native).balanceOf(address(strategy));
        console.log("CRV", crvBal);
        console.log("CVX", cvxBal);
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i]).balanceOf(address(strategy));
            console2.log(IERC20Extended(rewards[i]).symbol(), bal);
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
            console2.log(IERC20Extended(rewards[i]).symbol(), bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
        console.log("WETH", nativeBal);
        assertEq(crvBal, 0, "CRV not swapped");
        assertEq(crvBal, 0, "CVX not swapped");
        assertEq(nativeBal, 0, "Native not swapped");
    }

    function test_skipCurveSwap() external {
        strategy.resetRewards();
        strategy.resetRewardsV3();
        strategy.setCurveSwapMinAmount(0);

        _depositIntoVault(user, wantAmount);
        uint bal = vault.balance();
        skip(1 days);

        console.log("Harvest");
        strategy.harvest();
        assertEq(vault.balance(), bal, "Expected harvested 0");
    }

    function test_setNativeToWant() external {
        address[9] memory route;
        uint[3][4] memory params;
        route[0] = crv;
        vm.expectRevert();
        strategy.setNativeToWantRoute(route, params);

        route[0] = native;
        route[1] = crv;
        console.log("setNativeToWantRoute");
        strategy.setNativeToWantRoute(route, params);

        assertEq(strategy.nativeToWant().length, 2, "!route");
        assertEq(strategy.nativeToWant()[0], route[0], "!route 0");
        assertEq(strategy.nativeToWant()[1], route[1], "!route 1");
        assertEq(strategy.nativeToWantParams()[0][0], params[0][0], "!params");
        assertEq(strategy.nativeToCvxCRV(), 0, "amount != 0");
    }

    function test_rewardsWeight() external {
        console.log("setRewardWeight 0");
        strategy.setRewardWeight(0);
        assertEq(strategy.rewardWeight(), 0, "weight != 0");
        console.log("setRewardWeight 10000");
        strategy.setRewardWeight(10000);
        assertEq(strategy.rewardWeight(), 10000, "weight != 10000");
    }

    function test_rewardsV3() external {
        console.log("Add reward");
        strategy.addRewardV3(uniV3RewardPath, 10);
        deal(uniV3Reward, address(strategy), 1e20);
        console.log(IERC20Extended(uniV3Reward).symbol(), IERC20(uniV3Reward).balanceOf(address(strategy)));

        skip(1 days);
        console.log("Harvest");
        strategy.harvest();
        uint bal = IERC20(uniV3Reward).balanceOf(address(strategy));
        console.log(IERC20Extended(uniV3Reward).symbol(), bal);
        assertEq(bal, 0, "Extra reward not swapped");
    }
}