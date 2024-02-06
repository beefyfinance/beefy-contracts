// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Curve/StrategyConic.sol";
import "../../../contracts/BIFI/strategies/Curve/ConicZap.sol";
import "../../../contracts/BIFI/interfaces/common/IWrappedNative.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyConicTest is BaseStrategyTest {

    StrategyConic strategy;

    function createStrategy(address _impl) internal override returns (address) {
        // Conic calls Chainlink which will revert with "price too old" after we skip time
        // here we cache via mock current prices of all possible tokens
        cacheOraclePrices();

        if (_impl == a0) strategy = new StrategyConic();
        else strategy = StrategyConic(_impl);
        return address(strategy);
    }

    function test_zapIn() external {
        ConicZap zap = new ConicZap();
        IBeefyVault beefyVault = IBeefyVault(address(vault));
        address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

        vm.expectRevert('Beefy: Input token not present in pool');
        zap.estimateSwap(beefyVault, cvx, 1000);

        address tokenIn = strategy.depositToken();
        uint amount = 10000000000000000;
        (uint swapAmountIn, uint swapAmountOut, address swapTokenOut) = zap.estimateSwap(beefyVault, tokenIn, amount);
        uint amountMin = swapAmountOut * 995 / 1000; // 0.5%
        console.log('Estimate swap', swapAmountIn, swapAmountOut, amountMin);
        assertEq(swapAmountIn, amount, "swapAmountIn != amount");
        assertLt(swapAmountOut, swapAmountIn, "swapAmountOut >= swapAmountIn");
        assertEq(swapTokenOut, address(want), "swapTokenOut != want");

        deal(tokenIn, address(this), amount);
        if (tokenIn == strategy.native()) {
            console.log('Zap in native beefInETH');
            IWrappedNative(strategy.native()).withdraw(amount);
            zap.beefInETH{value: amount}(beefyVault, amountMin);
        } else {
            IERC20(tokenIn).approve(address(zap), type(uint).max);
            zap.beefIn(beefyVault, amountMin, tokenIn, amount);
        }

        assertEq(IERC20(zap.CNC()).balanceOf(address(zap)), 0);
        assertEq(IERC20(strategy.depositToken()).balanceOf(address(zap)), 0);
        assertEq(want.balanceOf(address(zap)), 0);
        assertEq(address(zap).balance, 0);

        uint mooBal = beefyVault.balanceOf(address(this));
        uint tokenBal = mooBal * beefyVault.balance() / beefyVault.totalSupply();
        console.log('Received tokenBal', tokenBal);
        assertGe(tokenBal, amountMin, "Balance < amountMin");
    }

    function test_zapOut() external {
        ConicZap zap = new ConicZap();
        IBeefyVault beefyVault = IBeefyVault(address(vault));
        address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

        vm.expectRevert('Beefy: desired token not present in pool');
        zap.estimateSwapOut(beefyVault, cvx, 1000);

        uint lpAmount = 10000;
        deal(address(want), address(this), lpAmount);
        want.approve(address(vault), lpAmount);
        vault.deposit(lpAmount);
        uint withdrawAmount = beefyVault.balanceOf(address(this));

        address tokenOut = strategy.depositToken();
        (uint swapAmountIn, uint swapAmountOut, address swapTokenIn) = zap.estimateSwapOut(beefyVault, tokenOut, withdrawAmount);
        uint amountMin = swapAmountOut * 999 / 1000; // 0.1%
        console.log('Estimate swapOut', swapAmountIn, swapAmountOut, amountMin);
        uint withdrawAmountAfterFee = withdrawAmount - (withdrawAmount * strategy.withdrawFee() / strategy.WITHDRAWAL_MAX());
        assertEq(swapAmountIn, withdrawAmountAfterFee, "swapAmountIn != amount");
        assertGt(swapAmountOut, swapAmountIn, "swapAmountOut < swapAmountIn");
        assertEq(swapTokenIn, address(want), "swapTokenIn != want");

        beefyVault.approve(address(zap), type(uint).max);
        zap.beefOutAndSwap(beefyVault, withdrawAmount, tokenOut, amountMin);

        assertEq(IERC20(zap.CNC()).balanceOf(address(zap)), 0);
        assertEq(IERC20(strategy.depositToken()).balanceOf(address(zap)), 0);
        assertEq(want.balanceOf(address(zap)), 0);

        uint tokenBal = (tokenOut == strategy.native())
            ? address(this).balance
            : IERC20(tokenOut).balanceOf(address(this));
        assertGe(tokenBal, amountMin, "Balance < amountMin");
    }

    function test_rewards() external {
        _depositIntoVault(user, wantAmount);
        skip(1 days);

        IRewardManager rewardManager = strategy.rewardManager();
        vm.prank(address(strategy));
        rewardManager.claimEarnings();

        for (uint i; i < strategy.rewardsLength(); ++i) {
            uint bal = IERC20(strategy.rewards(i)).balanceOf(address(strategy));
            console.log(IERC20Extended(strategy.rewards(i)).symbol(), bal);
        }

        console.log("Harvest");
        strategy.harvest();

        for (uint i; i < strategy.rewardsLength(); ++i) {
            uint bal = IERC20(strategy.rewards(i)).balanceOf(address(strategy));
            console.log(IERC20Extended(strategy.rewards(i)).symbol(), bal);
            assertEq(bal, 0, "Extra reward not swapped");
        }
    }

    address[] private oracleTokens = [
    0xdAC17F958D2ee523a2206206994597C13D831ec7,
    0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E,
    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
    0x853d955aCEf822Db058eb8505911ED77F175b99e,
    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
    0x6B175474E89094C44Da98b954EedeAC495271d0F,
    0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
    ];

    function cacheOraclePrices() internal {
        address chainlink = 0xd918685c42A248Ff471ef87e005718C4AaFe04B7;
        for (uint i; i < oracleTokens.length; i++) {
            bytes memory callData = abi.encodeWithSignature("getUSDPrice(address)", oracleTokens[i]);
            (, bytes memory res) = chainlink.staticcall(callData);
            uint price = abi.decode(res, (uint));
            vm.mockCall(chainlink, callData, abi.encode(price));
        }

        address frxEthOracle = 0x7EeA9d690162bc71Bb81B9BA83b53d4AD376F21C;
        bytes memory _callData = abi.encodeWithSignature("getUSDPrice(address)", 0x5E8422345238F34275888049021821E8E08CAa1f);
        (, bytes memory _res) = frxEthOracle.staticcall(_callData);
        uint _price = abi.decode(_res, (uint));
        vm.mockCall(frxEthOracle, _callData, abi.encode(_price));
    }

    receive() external payable {}
}