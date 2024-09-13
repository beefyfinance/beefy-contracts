// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyConvexStaking.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyConvexStakingTest is BaseStrategyTest {

    StrategyConvexStaking strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyConvexStaking();
        else strategy = StrategyConvexStaking(payable(_impl));
        return address(strategy);
    }

    address native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function beforeHarvest() internal override {
        addRewards();
    }

    function addRewards() internal {
//        vm.startPrank(strategy.owner());
//        strategy.addRewardV3(abi.encodePacked(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B, uint24(1), native), 1e18); // cvx
//        strategy.addRewardV3(abi.encodePacked(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, uint24(1), native), 1e16); // wsteth
//        strategy.addRewardV3(abi.encodePacked(0x365AccFCa291e7D3914637ABf1F7635dB165Bb09, uint24(1), native), 1e17); // fxn
//        strategy.setCurveSwapMinAmount(0);
//        vm.stopPrank();
    }

    function test_addRewards() external {
        vm.startPrank(strategy.owner());
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
        address[] memory routeToNative = strategy.rewardToNative(0);
        uint[3][4] memory swapParams = strategy.rewardToNativeParams(0);
        uint minAmount = strategy.rewards(0);
        assertEq(routeToNative[0], strategy.crv(), "!crv");
        assertEq(swapParams[0][0], 11, "!params");
        assertEq(minAmount, 1, "!minAmount");
        routeToNative = strategy.rewardToNative(1);
        assertEq(routeToNative[0], strategy.cvx(), "!cvx");
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
        print(strategy.nativeToWantRoute());

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

        addRewards();

        address[] memory rewards = new address[](strategy.rewardsLength() + strategy.rewardsV3Length());
        for(uint i; i < strategy.rewardsLength(); ++i) {
            rewards[i] = strategy.rewardToNative(i)[0];
        }
        for(uint i; i < strategy.rewardsV3Length(); ++i) {
            (address token, bytes memory path, uint min) = strategy.rewardsV3(i) ;
            rewards[strategy.rewardsLength() + i] = token;
            console.log("RewardV3", token, bytesToStr(path), min);
        }

        console.log("Claim rewards on Convex");
        strategy.staking().getReward(address(strategy));
        uint crvBal = IERC20(strategy.crv()).balanceOf(address(strategy));
        uint cvxBal = IERC20(strategy.cvx()).balanceOf(address(strategy));
        uint nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        console.log("CRV", crvBal);
        console.log("CVX", cvxBal);
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i]).balanceOf(address(strategy));
            console2.log(IERC20Extended(rewards[i]).symbol(), bal);
        }
        console.log("WETH", nativeBal);
//        deal(strategy.crv(), address(strategy), 1e20);
        deal(strategy.cvx(), address(strategy), 1e20);

        console.log("Harvest");
        strategy.harvest();
        crvBal = IERC20(strategy.crv()).balanceOf(address(strategy));
        cvxBal = IERC20(strategy.cvx()).balanceOf(address(strategy));
        nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        console.log("CRV", crvBal);
        console.log("CVX", cvxBal);
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i]).balanceOf(address(strategy));
            console2.log(IERC20Extended(rewards[i]).symbol(), bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
        console.log("WETH", nativeBal);
        assertEq(crvBal, 0, "CRV not swapped");
        assertEq(cvxBal, 0, "CVX not swapped");
        assertEq(nativeBal, 0, "Native not swapped");
    }

    function test_skipCurveSwap() external {
        vm.startPrank(strategy.keeper());
        strategy.resetRewards();
        strategy.resetRewardsV3();
        strategy.setCurveSwapMinAmount(0);
        vm.stopPrank();

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
        route[0] = strategy.crv();
        vm.prank(strategy.owner());
        vm.expectRevert();
        strategy.setNativeToWantRoute(route, params);

        route[0] = strategy.native();
        route[1] = strategy.crv();
        console.log("setNativeToWantRoute");
        vm.prank(strategy.owner());
        strategy.setNativeToWantRoute(route, params);

        assertEq(strategy.nativeToWantRoute().length, 2, "!route");
        assertEq(strategy.nativeToWantRoute()[0], route[0], "!route 0");
        assertEq(strategy.nativeToWantRoute()[1], route[1], "!route 1");
        assertEq(strategy.nativeToWantParams()[0][0], params[0][0], "!params");
        assertEq(strategy.nativeToWant(), 0, "amount != 0");
    }
}