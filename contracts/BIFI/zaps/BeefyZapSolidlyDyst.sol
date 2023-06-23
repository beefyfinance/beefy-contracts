// SPDX-License-Identifier: GPLv2

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.

// @author Wivern & Weso for Beefy.Finance
// @notice This contract adds liquidity to Solidly compatible liquidity pair pools and stake.

pragma solidity >=0.7.0;

import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin-4/contracts/utils/Address.sol';
import "@openzeppelin-4/contracts/utils/math/SafeMath.sol";
import '@uniswap/lib/contracts/libraries/Babylonian.sol';
import '../interfaces/common/ISolidlyPair.sol';
import '../interfaces/common/ISolidlyRouter.sol';
import '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol';

interface IERC20Extended { 
    function decimals() external view returns (uint256);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IBeefyVaultV6 is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function want() external pure returns (address);
}

interface IDystRouter {
    function wmatic() external view returns (address);
}

contract BeefyZapSolidlyDyst {
    using LowGasSafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVaultV6;

    ISolidlyRouter public immutable router;
    address public immutable WETH;
    uint256 public constant minimumAmount = 1000;
    
    constructor(address _router, address _WETH) {
        router = ISolidlyRouter(_router);
        WETH = _WETH;
    }

    function beefInETH(address beefyVault, uint256 tokenAmountOutMin) external payable {
        require(msg.value >= minimumAmount, 'Beefy: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();

        _swapAndStake(beefyVault, tokenAmountOutMin, WETH);
    }

    function beefIn(address beefyVault, uint256 tokenAmountOutMin, address tokenIn, uint256 tokenInAmount) external {
        require(tokenInAmount >= minimumAmount, 'Beefy: Insignificant input amount');
        require(IERC20(tokenIn).allowance(msg.sender, address(this)) >= tokenInAmount, 'Beefy: Input token is not approved');

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);

        _swapAndStake(beefyVault, tokenAmountOutMin, tokenIn);
    }

    function beefOut(address beefyVault, uint256 withdrawAmount) external {
        (IBeefyVaultV6 vault, ISolidlyPair pair) = _getVaultPair(beefyVault);

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
        (IBeefyVaultV6 vault, ISolidlyPair pair) = _getVaultPair(beefyVault);
        address token0 = pair.token0();
        address token1 = pair.token1();
        require(token0 == desiredToken || token1 == desiredToken, 'Beefy: desired token not present in liqudity pair');

        vault.safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);
        _removeLiquidity(address(pair), address(this));

        address swapToken = token1 == desiredToken ? token0 : token1;
        address[] memory path = new address[](2);
        path[0] = swapToken;
        path[1] = desiredToken;

        _approveTokenIfNeeded(path[0], address(router));
        router.swapExactTokensForTokensSimple(IERC20(swapToken).balanceOf(address(this)), desiredTokenOutMin, path[0], path[1], pair.stable(), address(this), block.timestamp);

        _returnAssets(path);
    }

    function _removeLiquidity(address pair, address to) private {
        IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = ISolidlyPair(pair).burn(to);

        require(amount0 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    function _getVaultPair(address beefyVault) private pure returns (IBeefyVaultV6 vault, ISolidlyPair pair) {
        vault = IBeefyVaultV6(beefyVault);
        pair = ISolidlyPair(vault.want());
    }

    function _swapAndStake(address beefyVault, uint256 tokenAmountOutMin, address tokenIn) private {
        (IBeefyVaultV6 vault, ISolidlyPair pair) = _getVaultPair(beefyVault);

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        require(reserveA > minimumAmount && reserveB > minimumAmount, 'Beefy: Liquidity pair reserves too low');

        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, 'Beefy: Input token not present in liqudity pair');

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
        uint256[] memory swapedAmounts = router
            .swapExactTokensForTokensSimple(swapAmountIn, tokenAmountOutMin, path[0], path[1], pair.stable(), address(this), block.timestamp);

        _approveTokenIfNeeded(path[1], address(router));
        (,, uint256 amountLiquidity) = router
            .addLiquidity(path[0], path[1], pair.stable(), fullInvestment.sub(swapedAmounts[0]), swapedAmounts[1], 1, 1, address(this), block.timestamp);

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

    function _getSwapAmount(ISolidlyPair pair, uint256 investmentA, uint256 reserveA, uint256 reserveB, address tokenA, address tokenB) private view returns (uint256 swapAmount) {
        uint256 halfInvestment = investmentA / 2;

        if (pair.stable()) {
            swapAmount = _getStableSwap(pair, investmentA, halfInvestment, tokenA, tokenB);
        } else {
            uint256 nominator = pair.getAmountOut(halfInvestment, tokenA);
            uint256 denominator = halfInvestment * reserveB.sub(nominator) / reserveA.add(halfInvestment);
            swapAmount = investmentA.sub(Babylonian.sqrt(halfInvestment * halfInvestment * nominator / denominator));
        }
    }

    function _getStableSwap(ISolidlyPair pair, uint256 investmentA, uint256 halfInvestment, address tokenA, address tokenB) private view returns (uint256 swapAmount) {
        uint out = pair.getAmountOut(halfInvestment, tokenA);
        (uint amountA, uint amountB,) = router.quoteAddLiquidity(tokenA, tokenB, pair.stable(), halfInvestment, out);
                
        amountA = amountA * 1e18 / 10**IERC20Extended(tokenA).decimals();
        amountB = amountB * 1e18 / 10**IERC20Extended(tokenB).decimals();
        out = out * 1e18 / 10**IERC20Extended(tokenB).decimals();
        halfInvestment = halfInvestment * 1e18 / 10**IERC20Extended(tokenA).decimals();
                
        uint ratio = out * 1e18 / halfInvestment * amountA / amountB; 
                
        return investmentA * 1e18 / (ratio + 1e18);
    }

    function estimateSwap(address beefyVault, address tokenIn, uint256 fullInvestmentIn) public view returns(uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenOut) {
        checkWETH();
        (, ISolidlyPair pair) = _getVaultPair(beefyVault);

        bool isInputA = pair.token0() == tokenIn;
        require(isInputA || pair.token1() == tokenIn, 'Beefy: Input token not present in liqudity pair');

        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        (reserveA, reserveB) = isInputA ? (reserveA, reserveB) : (reserveB, reserveA);

        swapTokenOut = isInputA ? pair.token1() : pair.token0();
        swapAmountIn = _getSwapAmount(pair, fullInvestmentIn, reserveA, reserveB, tokenIn, swapTokenOut);
        swapAmountOut = pair.getAmountOut(swapAmountIn, tokenIn); 
    }

    function checkWETH() public view returns (bool isValid) {
        isValid = WETH == IDystRouter(address(router)).wmatic();
        require(isValid, 'Beefy: WETH address not matching Router.weth()');
    }

    function _approveTokenIfNeeded(address token, address spender) private {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }
}
