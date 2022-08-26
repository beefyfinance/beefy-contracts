// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/utils/math/Math.sol";

import "../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/common/IUniswapV2Pair.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IBeefyVault is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function want() external pure returns (address); // Beefy Vault V6
    function token() external pure returns (address); // Beefy Vault V5
    function balance() external pure returns (uint256);
    function totalSupply() external pure returns (uint256);
    function strategy() external pure returns (address);
}

interface IStrategy {
    function withdrawalFee() external view returns (uint256);
}

contract BeefyZapOneInchUniswapV2Compatible {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVault;

    address public immutable oneInchRouter;
    address public immutable WETH;
    uint256 public constant minimumAmount = 1000;


    constructor(address _oneInchRouter, address _WETH) {
        // Safety checks to ensure WETH token address
        IWETH(_WETH).deposit{value: 0}();
        IWETH(_WETH).withdraw(0); 

        oneInchRouter = _oneInchRouter;
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

    function beefInETH (address beefyVault, IUniswapRouterETH router, bytes memory token0, bytes memory token1) external payable {
        require(msg.value >= minimumAmount, 'Beefy: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();
        _swapAndStake(beefyVault, WETH, router, token0, token1);
    }

    function beefIn (address beefyVault, IUniswapRouterETH router,  address inputToken, uint256 tokenInAmount, bytes memory token0, bytes memory token1) external {
        require(tokenInAmount >= minimumAmount, 'Beefy: Insignificant input amount');
        require(IERC20(inputToken).allowance(msg.sender, address(this)) >= tokenInAmount, 'Beefy: Input token is not approved');

        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), tokenInAmount);

        _swapAndStake(beefyVault, inputToken, router, token0, token1);
    }

    function beefOut (address beefyVault, uint256 withdrawAmount) external {
        (IBeefyVault vault, IUniswapV2Pair pair) = _getVaultPair(beefyVault);

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

    function beefOutAndSwap(address beefyVault, uint256 withdrawAmount, address desiredToken, bytes memory dataToken0, bytes memory dataToken1) external {
        (IBeefyVault vault, IUniswapV2Pair pair) = _getVaultPair(beefyVault);

        vault.safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);
        _removeLiquidity(address(pair), address(this));

        address[] memory path = new address[](3);
        path[0] = pair.token0();
        path[1] = pair.token1();
        path[2] = desiredToken;

        _approveTokenIfNeeded(path[0], address(oneInchRouter));
        _approveTokenIfNeeded(path[1], address(oneInchRouter));

        if (desiredToken != path[0]) {
            _swapViaOneInch(path[0], dataToken0);
        }

        if (desiredToken != path[1]) {
            _swapViaOneInch(path[1], dataToken1);
        }

        _returnAssets(path);
    }

    function _removeLiquidity(address pair, address to) private {
        IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);

        require(amount0 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
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
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 extliquidity = _mintFee(pair, reserve0, reserve1, totalSupply);
        totalSupply += extliquidity;

        amt0 = liquidity * balance0 / totalSupply;
        amt1 = liquidity * balance1 / totalSupply;
    }

       function _mintFee(IUniswapV2Pair pair, uint112 _reserve0, uint112 _reserve1, uint256 totalSupply) private view returns (uint256 liquidity) {
        uint _kLast = pair.kLast(); // gas savings
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0) * _reserve1);
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply * rootK - rootKLast;
                    uint denominator = rootK * 5 + rootKLast;
                    liquidity = numerator / denominator;
                }
            }
    }

    function _getVaultPair (address beefyVault) private pure returns (IBeefyVault vault, IUniswapV2Pair pair) {
        vault = IBeefyVault(beefyVault);

        try vault.want() returns (address pairAddress) {
            pair = IUniswapV2Pair(pairAddress); // Vault V6
        } catch {
            pair = IUniswapV2Pair(vault.token()); // Vault V5
        }
    }

    function _swapAndStake(address beefyVault, address inputToken, IUniswapRouterETH router, bytes memory token0, bytes memory token1) private {
        (IBeefyVault vault, IUniswapV2Pair pair) = _getVaultPair(beefyVault);

        address[] memory path = new address[](3);
        path[0] = pair.token0();
        path[1] = pair.token1();
        path[2] = inputToken;

        if (inputToken != path[0]) {
            _swapViaOneInch(inputToken, token0);
        }

        if (inputToken != path[1]) {
            _swapViaOneInch(inputToken, token1);
        }

        _approveTokenIfNeeded(path[0], address(router));
        _approveTokenIfNeeded(path[1], address(router));
        uint256 lp0Amt = IERC20(path[0]).balanceOf(address(this));
        uint256 lp1Amt = IERC20(path[1]).balanceOf(address(this));
        (,, uint256 amountLiquidity) = router
            .addLiquidity(path[0], path[1], lp0Amt, lp1Amt, 1, 1, address(this), block.timestamp);

        _approveTokenIfNeeded(address(pair), address(vault));
        vault.deposit(amountLiquidity);

        vault.safeTransfer(msg.sender, vault.balanceOf(address(this)));
        _returnAssets(path);
    }

    function _swapViaOneInch(address _inputToken, bytes memory _callData) internal returns (uint) {
        
        _approveTokenIfNeeded(_inputToken, address(oneInchRouter));

        (bool success, bytes memory retData) = oneInchRouter.call(_callData);

        propagateError(success, retData, "1inch");

        require(success == true, "calling 1inch got an error");
        (uint actualAmount, ) = abi.decode(retData, (uint, uint));
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