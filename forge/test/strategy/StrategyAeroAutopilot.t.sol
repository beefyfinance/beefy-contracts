// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Velodrome/StrategyAeroAutopilot.sol";
import "./BaseAllToNativeFactoryTest.t.sol";
import {MellowVeloHelper} from "../../../contracts/BIFI/strategies/Velodrome/MellowVeloHelper.sol";
import {SimpleSwapper} from "../../../contracts/BIFI/infra/SimpleSwapper.sol";

contract StrategyAeroAutopilotTest is BaseAllToNativeFactoryTest {

    StrategyAeroAutopilot strategy;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) strategy = new StrategyAeroAutopilot();
        else strategy = StrategyAeroAutopilot(payable(_impl));
        return address(strategy);
    }

    function beforeHarvest() internal override {
        deal(BaseAllToNativeFactoryStrat(payable(strategy)).rewards(0), address(strategy), 1000e18);
        vm.startPrank(strategy.keeper());
        strategy.setRewardMinAmount(strategy.native(), 0.001 ether);
        vm.stopPrank();
    }

    function test_apy() public {
        vm.startPrank(strategy.keeper());
        strategy.setRewardMinAmount(strategy.native(), 0);
        vm.stopPrank();

        uint start = 1770385170;
        uint secs = block.timestamp - start;
        uint ppsInit = 1 ether;
        console.log(ppsInit);
        uint ppsLast = IVault(strategy.vault()).getPricePerFullShare();
        uint lastHarvest = strategy.lastHarvest();
//        deal(strategy.native(), address(strategy), 0.05 ether);
        strategy.harvest();
        uint ppsNow = IVault(strategy.vault()).getPricePerFullShare();
        console.log(ppsNow);
        console.log("period", secs);
        uint growth = (ppsNow - ppsInit) / secs * 31536000;
        console.log("apr %18e", growth * 1e18 / ppsInit * 100);


        secs = block.timestamp - lastHarvest;
        console.log(ppsLast);
        console.log("period", secs);
        growth = (ppsNow - ppsLast) / secs * 31536000;
        console.log("apr since lastH %18e", growth * 1e18 / ppsLast * 100);
    }

    address[] lps = [0xB9DB6804e84D960E139A2BdC33bfC30f8fb689Fe, 0xcd975e6a5F55137755487F0918b8ca74aCCe7925, 0x0Df5f2662e4a8C801c04D83Df717476509816250, 0x331efe99464d3A1CAD008c720e699F7FD318FEF6];

    function test_helperRates() public {
        MellowVeloHelper h = new MellowVeloHelper();
        uint[] memory rates = h.rewardRate(lps);
        (uint[] memory ratesNew,) = h.rewardRateNew(lps);
        for (uint i; i < lps.length; i++) {
            string memory s = IERC20Extended(lps[i]).symbol();
            assertApproxEqAbs(rates[i], ratesNew[i], 1, s);
            console.log("%s %18e %18e", s, rates[i], rates[i] * 31536000);
        }
    }

    function test_toWantViaSwapper() public {
        _depositIntoVault(user, wantAmount);
        skip(delay);
        strategy.harvest();

        bytes memory swapData;
        SimpleSwapper swapper = SimpleSwapper(strategy.swapper());
        vm.startPrank(strategy.keeper());
        swapper.setSwapInfo(strategy.depositToken(), strategy.want(), SimpleSwapper.SwapInfo(address(1), swapData, 0));
        vm.stopPrank();

        skip(delay);
        deal(BaseAllToNativeFactoryStrat(payable(strategy)).rewards(0), address(strategy), 1000e18);
        vm.expectRevert();
        strategy.harvest();
    }

    // custom test as balanceOfPool is always 0 as strat simply holds want
    function test_depositAndWithdraw() public override {
        _depositIntoVault(user, wantAmount);
        assertEq(want.balanceOf(address(user)), 0, "User balance != 0 after deposit");
        assertGe(vault.balance(), wantAmount, "Vault balance < wantAmount");

        uint vaultBal = vault.balance();
        uint balOfPool = strategy.balanceOfPool();
        uint balOfWant = strategy.balanceOfWant();
        assertGe(balOfWant, wantAmount, "balOfPool < wantAmount"); // if deposit fee could be GT want * 99 / 100
        assertEq(balOfWant, vaultBal, "balOfPool != vaultBal");
        assertEq(balOfPool, 0, "Strategy.balanceOfPool != 0");

        console.log("Panic");
        vm.prank(strategy.keeper());
        strategy.panic();
        uint vaultBalAfterPanic = vault.balance();
        uint balOfPoolAfterPanic = strategy.balanceOfPool();
        uint balOfWantAfterPanic = strategy.balanceOfWant();
        // Vault balances are correct after panic.
        assertEq(vaultBalAfterPanic, vaultBal, "vaultBalAfterPanic"); // vaultBal * 99 / 100
        assertEq(balOfWantAfterPanic, balOfWant, "balOfWantAfterPanic != balOfWant");
        assertEq(balOfPoolAfterPanic, 0, "balOfPoolAfterPanic != 0");

        console.log("Unpause");
        vm.prank(strategy.keeper());
        strategy.unpause();
        uint vaultBalAfterUnpause = vault.balance();
        uint balOfPoolAfterUnpause = strategy.balanceOfPool();
        uint balOfWantAfterUnpause = strategy.balanceOfWant();
        assertEq(vaultBalAfterUnpause, vaultBalAfterPanic, "vaultBalAfterUnpause");
        assertEq(balOfWantAfterUnpause, balOfWant, "balOfWantAfterUnpause != balOfWant");
        assertEq(balOfPoolAfterUnpause, 0, "balOfPoolAfterUnpause != 0");

        console.log("Withdrawing all");
        user.withdrawAll(vault);

        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, wantAmount, "Expected wantBalanceFinal <= wantAmount");
        assertGt(wantBalanceFinal, wantAmount * 99 / 100, "Expected wantBalanceFinal > wantAmount * 99 / 100");
    }

}