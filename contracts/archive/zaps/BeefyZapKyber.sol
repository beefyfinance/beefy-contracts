// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/utils/math/Math.sol";

import "../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/common/IUniswapV2Pair.sol";
import "../interfaces/common/ISolidlyPair.sol";
import "../interfaces/common/ISolidlyRouter.sol";
import "./zapInterfaces/IWETH.sol";
import "./zapInterfaces/IBeefyVault.sol";
import "./zapInterfaces/IStrategy.sol";
import "./zapInterfaces/IERC20Extended.sol";

contract BeefyZapKyber {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVault;

    address public immutable aggregationRouter;
    address public immutable WETH;
    uint256 public constant minimumAmount = 1000;


    constructor(address _aggregationRouter, address _WETH) {
        // Safety checks to ensure WETH token address
        IWETH(_WETH).deposit{value: 0}();
        IWETH(_WETH).withdraw(0); 

        aggregationRouter = _aggregationRouter;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    function propagateError(
        bool success,
        bytes memory data,
        string memory errorMessage
    ) public pure {
        // Forward error message from call/delegatecall
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    function beefInETH (address beefyVault, bytes memory token0, bytes memory token1) external payable {
        require(msg.value >= minimumAmount, 'Beefy: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();
        _swapAndStake(beefyVault, WETH, WETH, token0, token1);
    }

    function beefIn (address beefyVault, address inputToken, uint256 tokenInAmount, bytes memory token0, bytes memory token1) public {
        require(tokenInAmount >= minimumAmount, 'Beefy: Insignificant input amount');
        require(IERC20(inputToken).allowance(msg.sender, address(this)) >= tokenInAmount, 'Beefy: Input token is not approved');

        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), tokenInAmount);

        _swapAndStake(beefyVault, inputToken, inputToken, token0, token1);
    }

    function beefOut (address beefyVault, uint256 withdrawAmount) external {
        address[] memory tokens = _beefOut(beefyVault, withdrawAmount);
         _returnAssets(tokens);
    }

    function _beefOut (address beefyVault, uint256 withdrawAmount) internal returns (address[] memory tokens) {
        (IBeefyVault vault, IUniswapV2Pair pair) = _getVaultPair(beefyVault);

        IERC20(beefyVault).safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);

        _removeLiquidity(address(pair), address(this));

        tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();
    }

    function beefOutAndSwap(address beefyVault, uint256 withdrawAmount, address desiredToken, bytes memory dataToken0, bytes memory dataToken1) external {
        (IBeefyVault vault, IUniswapV2Pair pair) = _getVaultPair(beefyVault);

        vault.safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);
        _removeLiquidity(address(pair), address(this));

        address[] memory path = new address[](3);
        path[0] = pair.token0();
        path[1] = pair.token1();
        path[2] = desiredToken;

        _approveTokenIfNeeded(path[0], address(aggregationRouter));
        _approveTokenIfNeeded(path[1], address(aggregationRouter));

        if (desiredToken != path[0]) {
            _swapViaKyber(path[0], dataToken0);
        }

        if (desiredToken != path[1]) {
            _swapViaKyber(path[1], dataToken1);
        }

        _returnAssets(path);
    }
    function beefOutAndReInvest(address fromVault, address toVault, uint256 mooTokenAmount, bytes memory token0ToFrom, bytes memory token1ToFrom) external {
        _beefOut(fromVault, mooTokenAmount);
        (, IUniswapV2Pair pair) = _getVaultPair(fromVault);
        address token0 = pair.token0();
        address token1 = pair.token1();
        _swapAndStake(toVault, token0, token1, token0ToFrom, token1ToFrom);
    }

    function _removeLiquidity(address pair, address to) private {
        IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);

        require(amount0 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    function quoteStableAddLiquidityRatio(IBeefyVault beefyVault) external view returns (uint256 ratio0to1) {
            (,IUniswapV2Pair pairAddress) = _getVaultPair(address(beefyVault));
            ISolidlyPair pair = ISolidlyPair(address(pairAddress));
            address tokenA = pair.token0();
            address tokenB = pair.token1();

            uint256 investment = 1e18;
            uint out = pair.getAmountOut(investment, tokenA);
            ISolidlyRouter router = ISolidlyRouter(IStrategy(beefyVault.strategy()).unirouter());
            (uint amountA, uint amountB,) = router.quoteAddLiquidity(tokenA, tokenB, pair.stable(), investment, out);
                
            amountA = amountA * 1e18 / 10**IERC20Extended(tokenA).decimals();
            amountB = amountB * 1e18 / 10**IERC20Extended(tokenB).decimals();
            out = out * 1e18 / 10**IERC20Extended(tokenB).decimals();
            investment = investment * 1e18 / 10**IERC20Extended(tokenA).decimals();
                
            uint ratio = out * 1e18 / investment * amountA / amountB; 
                
            return investment * 1e18 / (ratio + 1e18);
    }

    function quoteRemoveLiquidity(IBeefyVault beefyVault, uint256 mooTokenAmt) external view returns (uint256 amt0, uint256 amt1, address token0, address token1) {
        uint256 withdrawFee = IStrategy(beefyVault.strategy()).withdrawalFee();
        uint256 liquidity = mooTokenAmt * beefyVault.balance() / beefyVault.totalSupply();
        uint256 fee = withdrawFee > 0 ? liquidity * withdrawFee / 10000 : 0;
        liquidity = liquidity - fee;
        
        (, IUniswapV2Pair pair) = _getVaultPair(address(beefyVault));

        token0 = pair.token0();
        token1 = pair.token1();

        uint256 balance0 = IERC20(token0).balanceOf(address(pair));
        uint256 balance1 = IERC20(token1).balanceOf(address(pair));

        uint256 totalSupply = pair.totalSupply();

        amt0 = liquidity * balance0 / totalSupply;
        amt1 = liquidity * balance1 / totalSupply;
    }

    function _getVaultPair (address beefyVault) private pure returns (IBeefyVault vault, IUniswapV2Pair pair) {
        vault = IBeefyVault(beefyVault);

        try vault.want() returns (address pairAddress) {
            pair = IUniswapV2Pair(pairAddress); // Vault V6
        } catch {
            pair = IUniswapV2Pair(vault.token()); // Vault V5
        }
    }

    function _getSolidType (address pair) private view returns (bool isSolidPair, bool stable) {
        ISolidlyPair solidPair = ISolidlyPair(pair);
        try solidPair.stable() returns (bool stablePair) {
            isSolidPair = true;
            stable = stablePair;
        } catch {
            isSolidPair = false;
        }
    }

    function _swapAndStake(address beefyVault, address inputToken0, address inputToken1, bytes memory token0, bytes memory token1) private {
        (IBeefyVault vault, IUniswapV2Pair pair) = _getVaultPair(beefyVault);

        address[] memory path;
        if (inputToken0 == inputToken1) {
            path = new address[](3);
            path[0] = pair.token0();
            path[1] = pair.token1();
            path[2] = inputToken0;
        } else {
            path = new address[](4);
            path[0] = pair.token0();
            path[1] = pair.token1();
            path[2] = inputToken0;
            path[3] = inputToken1;
        }

        if (inputToken0 != path[0]) {
            _swapViaKyber(inputToken0, token0);
        }

        if (inputToken1 != path[1]) {
            _swapViaKyber(inputToken1, token1);
        }

        address router = IStrategy(vault.strategy()).unirouter();
        (bool isSolidPair, bool stable) = _getSolidType(address(pair));

        _approveTokenIfNeeded(path[0], address(router));
        _approveTokenIfNeeded(path[1], address(router));
        uint256 lp0Amt = IERC20(path[0]).balanceOf(address(this));
        uint256 lp1Amt = IERC20(path[1]).balanceOf(address(this));

        uint256 amountLiquidity;
        if (!isSolidPair) {
            (,, amountLiquidity) = IUniswapRouterETH(router)
            .addLiquidity(path[0], path[1], lp0Amt, lp1Amt, 1, 1, address(this), block.timestamp);
        } else {
            (,, amountLiquidity) = ISolidlyRouter(router)
            .addLiquidity(path[0], path[1], stable,  lp0Amt, lp1Amt, 1, 1, address(this), block.timestamp);
        }

        _approveTokenIfNeeded(address(pair), address(vault));
        vault.deposit(amountLiquidity);

        vault.safeTransfer(msg.sender, vault.balanceOf(address(this)));
        _returnAssets(path);
    }

    function _swapViaKyber(address _inputToken, bytes memory _callData) internal returns (uint) {
        
        _approveTokenIfNeeded(_inputToken, address(aggregationRouter));

        (bool success, bytes memory retData) = aggregationRouter.call(_callData);

        propagateError(success, retData, "kyber");

        require(success == true, "calling Kyber got an error");
        uint actualAmount = abi.decode(retData, (uint));
        return actualAmount;
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

    function _approveTokenIfNeeded(address token, address spender) private {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, type(uint).max);
        }
    }

}