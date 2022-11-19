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
    address constant ldo = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address constant usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant uniV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24[] fee500 = [500];
    uint24[] fee3000 = [3000];
    bytes nativeToUsdc = routeToPath(route(native, usdc), fee500);

//     apeUsd-fraxbp
    IERC20Like want = IERC20Like(0x04b727C7e246CA70d496ecF52E6b6280f3c8077D);
    address pool = 0x04b727C7e246CA70d496ecF52E6b6280f3c8077D;
    address zap = 0x08780fb7E580e492c1935bEe4fA5920b94AA95Da;
    uint pid = 103;
    uint poolSize = 3;
    uint depositIndex = 2;
    uint useUnderlying = 0;
    uint depositNative = 0;
    uint[] params = [poolSize, depositIndex, useUnderlying, depositNative];
    address unirouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24[] fee = [500];
    bytes nativeToDepositPath = routeToPath(route(native, usdc), fee);
    address[] nativeToDepositRoute = new address[](0);

    address[] rewardsV3 = new address[](0);
//    address[] rewardsV3 = [ldo, native];
    uint24[] rewardsV3Fee = [3000];

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