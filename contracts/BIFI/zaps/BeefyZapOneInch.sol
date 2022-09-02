// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/utils/math/Math.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";

import "../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/common/IUniswapV2Pair.sol";
import "../interfaces/common/ISolidlyPair.sol";
import "../interfaces/common/ISolidlyRouter.sol";

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
    function unirouter() external view returns (address);
}

interface IERC20Extended {
    function decimals() external view returns (uint256);
}

interface IBeefyDataSource {
    function feeData(address factory) external view returns (uint rootKInteger, uint rootKLastInteger);
    function isSolidPair(address factory) external view returns (bool);
}

contract BeefyZapOneInch is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVault;

    IBeefyDataSource public dataSource;
    address public immutable oneInchRouter;
    address public immutable WETH;
    uint256 public constant minimumAmount = 1000;


    constructor(address _oneInchRouter, address _WETH, address _dataSource) {
        // Safety checks to ensure WETH token address
        IWETH(_WETH).deposit{value: 0}();
        IWETH(_WETH).withdraw(0); 

        oneInchRouter = _oneInchRouter;
        dataSource = IBeefyDataSource(_dataSource);
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
        (IBeefyVault vault, IUniswapV2Pair pair,) = _getVaultPair(beefyVault);

        IERC20(beefyVault).safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);

        _removeLiquidity(address(pair), address(this));

        tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();
    }

    function beefOutAndSwap(address beefyVault, uint256 withdrawAmount, address desiredToken, bytes memory dataToken0, bytes memory dataToken1) external {
        (IBeefyVault vault, IUniswapV2Pair pair, bool singleAsset) =  _getVaultPair(beefyVault);
        vault.safeTransferFrom(msg.sender, address(this), withdrawAmount);
        vault.withdraw(withdrawAmount);

       if (!singleAsset) {
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
        } else {
            address[] memory path = new address[](2);
            path[0] = IBeefyVault(beefyVault).want();
            path[1] = desiredToken;

            _approveTokenIfNeeded(path[0], address(oneInchRouter));

            _swapViaOneInch(path[0], dataToken0);

            _returnAssets(path);
        }
    }
    function beefOutAndReInvest(address fromMooVault, address toMooVault, uint256 mooTokenAmount, bytes memory token0ToFrom, bytes memory token1ToFrom) external {
        (IBeefyVault vault, IUniswapV2Pair pair, bool singleAsset) = _getVaultPair(fromMooVault);
        (,,bool toSingleAsset) = _getVaultPair(toMooVault);

        address token0; 
        address token1;
        if (!singleAsset) {
            _beefOut(fromMooVault, mooTokenAmount);
            token0 = pair.token0();
            token1 = pair.token1();
            if (!toSingleAsset) {
                _swapAndStake(toMooVault, token0, token1, token0ToFrom, token1ToFrom);   
            } else {
                _swapAndStake(toMooVault, token0, token0ToFrom);
                _swapAndStake(toMooVault, token1, token1ToFrom);
            }
        } else {
            vault.safeTransferFrom(msg.sender, address(this), mooTokenAmount);
            vault.withdraw(mooTokenAmount);
            token0 = vault.want();
            token1 = token0;
            toSingleAsset ? _swapAndStake(toMooVault, token0, token0ToFrom) : _swapAndStake(toMooVault, token0, token1, token0ToFrom, token1ToFrom);
        }
    }

    function _removeLiquidity(address pair, address to) private {
        IERC20(pair).safeTransfer(pair, IERC20(pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(pair).burn(to);

        require(amount0 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    function quoteStableAddLiquidityRatio(IBeefyVault beefyVault) external view returns (uint256 ratio0to1) {
            (,IUniswapV2Pair pairAddress,) = _getVaultPair(address(beefyVault));
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
        
        (, IUniswapV2Pair pair,) = _getVaultPair(address(beefyVault));
        (bool isSolidPair,) = _getSolidType(address(pair));

        token0 = pair.token0();
        token1 = pair.token1();

        uint256 balance0 = IERC20(token0).balanceOf(address(pair));
        uint256 balance1 = IERC20(token1).balanceOf(address(pair));

        uint256 totalSupply = pair.totalSupply();

        if (!isSolidPair) {
            (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
            uint256 extliquidity = _mintFee(pair, reserve0, reserve1, totalSupply);
            totalSupply += extliquidity;
        }

        amt0 = liquidity * balance0 / totalSupply;
        amt1 = liquidity * balance1 / totalSupply;
    }

    function _mintFee(IUniswapV2Pair pair, uint112 _reserve0, uint112 _reserve1, uint256 totalSupply) private view returns (uint256 liquidity) {
        uint _kLast = pair.kLast();
        address factory =  pair.factory();
        (uint rootKInteger, uint rootKLastInteger) = dataSource.feeData(factory);
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0) * _reserve1);
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply * (rootK - rootKLast) * rootKLastInteger;
                    uint denominator = rootK * rootKInteger + (rootKLast * rootKLastInteger);
                    liquidity = numerator / denominator;
                }
            }
    }

    function _getVaultPair (address beefyVault) private view returns (IBeefyVault vault, IUniswapV2Pair pair, bool singleAsset) {
        vault = IBeefyVault(beefyVault);

        try vault.want() returns (address pairAddress) {
            pair = IUniswapV2Pair(pairAddress); // Vault V6
        } catch {
            pair = IUniswapV2Pair(vault.token()); // Vault V5
        }

        try pair.token0() returns (address) {
            singleAsset = false;
        } catch {
            singleAsset = true;
        }
    }

    function _getSolidType (address pair) private view returns (bool isSolidPair, bool stable) {
        ISolidlyPair solidPair = ISolidlyPair(pair);
        address factory = solidPair.factory();
        isSolidPair = dataSource.isSolidPair(factory);
        stable = isSolidPair ? solidPair.stable() : false;
    }

    function _swapAndStake(address _vault, address _inputToken, bytes memory _token0) private {
        IBeefyVault vault = IBeefyVault(_vault);
        address[] memory path;
        path = new address[](2);
        path[0] = vault.want();
        path[1] = _inputToken;

        _swapViaOneInch(_inputToken, _token0);

        uint256 bal = IERC20(path[0]).balanceOf(address(this));

        _approveTokenIfNeeded(path[0], address(vault));
        vault.deposit(bal);

        vault.safeTransfer(msg.sender, vault.balanceOf(address(this)));
        _returnAssets(path);
    }
  

    function _swapAndStake(address beefyVault, address inputToken0, address inputToken1, bytes memory token0, bytes memory token1) private {
        (IBeefyVault vault, IUniswapV2Pair pair, bool singleAsset) =  _getVaultPair(beefyVault);

        if (!singleAsset) {
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
                _swapViaOneInch(inputToken0, token0);
            }

            if (inputToken1 != path[1]) {
                _swapViaOneInch(inputToken1, token1);
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
        } else {
            _swapAndStake(beefyVault, inputToken0, token0);
        }
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

    function setDataSource(address _dataSource) external onlyOwner {
        dataSource = IBeefyDataSource(_dataSource);
    }

}