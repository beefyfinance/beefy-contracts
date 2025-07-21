// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-4/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-4/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRouter} from "../interfaces/velodrome-v2/IRouter.sol";
import {IPool} from "../interfaces/velodrome-v2/IPool.sol";
import {IBeefyVault} from "./zapInterfaces/IBeefyVault.sol";
import {IWETH} from "./zapInterfaces/IWETH.sol";
import {Babylonian} from "./libs/Babylonian.sol";

contract BeefyVelodromeV2Zap {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVault;

    IRouter public immutable router;
    address public immutable WETH;
    uint256 public constant minimumAmount = 1000;

    constructor(address _router, address _WETH) {
        router = IRouter(_router);
        WETH = _WETH;

        require(WETH == router.weth(), 'Beefy: WETH address not matching Router.weth()');
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    function beefInETH (address beefyVault, uint256 tokenAmountOutMin) external payable {
        require(msg.value >= minimumAmount, 'Beefy: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();

        _swapAndStake(beefyVault, tokenAmountOutMin, WETH);
    }

    function beefIn (address beefyVault, uint256 tokenAmountOutMin, address tokenIn, uint256 tokenInAmount) external {
        require(tokenInAmount >= minimumAmount, 'Beefy: Insignificant input amount');
        require(IERC20(tokenIn).allowance(msg.sender, address(this)) >= tokenInAmount, 'Beefy: Input token is not approved');

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);

        _swapAndStake(beefyVault, tokenAmountOutMin, tokenIn);
    }

    function beefOut (address beefyVault, uint256 withdrawAmount) external {
        (IBeefyVault vault, IPool pair) = _getVaultPair(beefyVault);

        IERC20(beefyVault).safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);

        if (pair.token0() != WETH && pair.token1() != WETH) {
            return _removeLiquidity(address(pair), msg.sender);
        }

        _removeLiquidity(address(pair), address(this));

        address[] memory tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();

        _returnAssets(tokens);
    }

    function beefOutAndSwap(address beefyVault, uint256 withdrawAmount, address desiredToken, uint256 desiredTokenOutMin) external {
        (IBeefyVault vault, IPool pair) = _getVaultPair(beefyVault);
        address token0 = pair.token0();
        address token1 = pair.token1();
        require(token0 == desiredToken || token1 == desiredToken, 'Beefy: desired token not present in liquidity pair');

        vault.safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);
        _removeLiquidity(address(pair), address(this));

        address swapToken = token1 == desiredToken ? token0 : token1;
        address[] memory path = new address[](2);
        path[0] = swapToken;
        path[1] = desiredToken;

        _approveTokenIfNeeded(path[0], address(router));
        _swapExactTokensForTokensSimple(IERC20(swapToken).balanceOf(address(this)), desiredTokenOutMin, path[0], path[1], pair.stable(), pair.factory(), address(this), block.timestamp);

        _returnAssets(path);
    }

    function _swapExactTokensForTokensSimple(
        uint amountIn,
        uint amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address factory,
        address to,
        uint deadline
    ) internal returns (uint256[] memory amounts) {
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route({
            from: tokenFrom,
            to: tokenTo,
            stable: stable,
            factory: factory
        });
        amounts = router.swapExactTokensForTokens(amountIn, amountOutMin, routes, to, deadline);
    }

    function _removeLiquidity(address pair, address to) private {
        IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = IPool(pair).burn(to);

        require(amount0 >= minimumAmount, 'Router: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= minimumAmount, 'Router: INSUFFICIENT_B_AMOUNT');
    }

    function _getVaultPair (address beefyVault) private pure returns (IBeefyVault vault, IPool pair) {
        vault = IBeefyVault(beefyVault);
        pair = IPool(vault.want());
    }

    function _swapAndStake(address beefyVault, uint256 tokenAmountOutMin, address tokenIn) private {
        (IBeefyVault vault, IPool pair) = _getVaultPair(beefyVault);
        require(pair.factory() == router.defaultFactory(), 'Beefy: Incompatible liquidity pair'); // router.addLiquidity adds to pair from router.defaultFactory()

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        require(reserveA > minimumAmount && reserveB > minimumAmount, 'Beefy: Liquidity pair reserves too low');

        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, 'Beefy: Input token not present in liquidity pair');

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = isInputA ? pair.token1() : pair.token0();

        uint256 fullInvestment = IERC20(tokenIn).balanceOf(address(this));
        uint256 swapAmountIn;
        if (isInputA) {
            swapAmountIn = _getSwapAmount(pair, fullInvestment, reserveA, reserveB, path[0], path[1]);
        } else {
            swapAmountIn = _getSwapAmount(pair, fullInvestment, reserveB, reserveA, path[0], path[1]);
        }

        _approveTokenIfNeeded(path[0], address(router));
        uint256[] memory swappedAmounts = _swapExactTokensForTokensSimple(swapAmountIn, tokenAmountOutMin, path[0], path[1], pair.stable(), pair.factory(), address(this), block.timestamp);

        _approveTokenIfNeeded(path[1], address(router));
        (,, uint256 amountLiquidity) = router
        .addLiquidity(path[0], path[1], pair.stable(), fullInvestment - swappedAmounts[0], swappedAmounts[1], 1, 1, address(this), block.timestamp);

        _approveTokenIfNeeded(address(pair), address(vault));
        vault.deposit(amountLiquidity);

        vault.safeTransfer(msg.sender, vault.balanceOf(address(this)));
        _returnAssets(path);
    }

    function _returnAssets(address[] memory tokens) private {
        uint256 balance;
        for (uint256 i; i < tokens.length; i++) {
            balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                if (tokens[i] == WETH) {
                    IWETH(WETH).withdraw(balance);
                    (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                    require(success, 'Beefy: ETH transfer failed');
                } else {
                    IERC20(tokens[i]).safeTransfer(msg.sender, balance);
                }
            }
        }
    }

    function _getSwapAmount(IPool pair, uint256 investmentA, uint256 reserveA, uint256 reserveB, address tokenA, address tokenB) private view returns (uint256 swapAmount) {
        uint256 halfInvestment = investmentA / 2;

        if (pair.stable()) {
            swapAmount = _getStableSwap(pair, investmentA, halfInvestment, tokenA, tokenB);
        } else {
            uint256 nominator = pair.getAmountOut(halfInvestment, tokenA);
            uint256 denominator = halfInvestment * (reserveB - nominator) / (reserveA + halfInvestment);
            swapAmount = investmentA - (Babylonian.sqrt(halfInvestment * halfInvestment * nominator / denominator));
        }
    }

    function _getStableSwap(IPool pair, uint256 investmentA, uint256 halfInvestment, address tokenA, address tokenB) private view returns (uint256 swapAmount) {
        uint out = pair.getAmountOut(halfInvestment, tokenA);
        (uint amountA, uint amountB,) = router.quoteAddLiquidity(tokenA, tokenB, pair.stable(), pair.factory(), halfInvestment, out);

        amountA = amountA * 1e18 / 10**IERC20Metadata(tokenA).decimals();
        amountB = amountB * 1e18 / 10**IERC20Metadata(tokenB).decimals();
        out = out * 1e18 / 10**IERC20Metadata(tokenB).decimals();
        halfInvestment = halfInvestment * 1e18 / 10**IERC20Metadata(tokenA).decimals();

        uint ratio = out * 1e18 / halfInvestment * amountA / amountB;

        return investmentA * 1e18 / (ratio + 1e18);
    }

    function estimateSwap(address beefyVault, address tokenIn, uint256 fullInvestmentIn) public view returns (uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenOut) {
        (, IPool pair) = _getVaultPair(beefyVault);
        require(pair.factory() == router.defaultFactory(), 'Beefy: Incompatible liquidity pair'); // router.addLiquidity adds to pair from router.defaultFactory()

        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, 'Beefy: Input token not present in liquidity pair');

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        (reserveA, reserveB) = isInputA ? (reserveA, reserveB) : (reserveB, reserveA);

        swapTokenOut = isInputA ? pair.token1() : pair.token0();
        swapAmountIn = _getSwapAmount(pair, fullInvestmentIn, reserveA, reserveB, tokenIn, swapTokenOut);
        swapAmountOut = pair.getAmountOut(swapAmountIn, tokenIn);
    }

    function _approveTokenIfNeeded(address token, address spender) private {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }
}
