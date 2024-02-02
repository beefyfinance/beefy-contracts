// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/IUniV3Quoter.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyPrisma.sol";
import "../../../contracts/BIFI/utils/UniswapV3Utils.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyPrismaTest is BaseStrategyTest {

    address uniV3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    uint minAmountToSwap = 1e17;
    uint24[] fee3000 = [3000];

    StrategyPrisma strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyPrisma();
        else strategy = StrategyPrisma(_impl);
        return address(strategy);
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
        strategy.setNativeToDepositPath(routeToPath(route(crv, crv), fee3000));
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
        address token = strategy.native();
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
        uint nativeBal = IERC20(strategy.native()).balanceOf(address(strategy));
        console.log("WETH", nativeBal);
        assertEq(nativeBal, 0, "Native not swapped");
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