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
import "./zapInterfaces/IWETH.sol";
import "./zapInterfaces/IBeefyVault.sol";
import "./zapInterfaces/IStrategy.sol";
import "./zapInterfaces/IERC20Extended.sol";
import "./zapInterfaces/IBeefyDataSource.sol";


// Aggregator Zap compatible with all single asset, uniswapv2, and solidly router Beefy Vaults. 
contract BeefyZapOneInch is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVault;

    // needed addresses for zap 
    IBeefyDataSource public dataSource;
    address public immutable oneInchRouter;
    address public immutable WETH;
    uint256 public constant minimumAmount = 1000;

    constructor(address _oneInchRouter, address _WETH, address _dataSource) {
        // Safety checks to ensure WETH token address
        IWETH(_WETH).deposit{value: 0}();
        IWETH(_WETH).withdraw(0);
        WETH = _WETH;

        oneInchRouter = _oneInchRouter;
        
        // data source is used to fetch pair fee info which we are unable to fetch on chain otherwise
        dataSource = IBeefyDataSource(_dataSource);
        
    }

    // Zap's main functions external and public functions
    function beefInETH (address _beefyVault, bytes calldata _token0, bytes calldata _token1) external payable {
        require(msg.value >= minimumAmount, 'Beefy: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();
        _swapAndStake(_beefyVault, WETH, WETH, _token0, _token1);
    }

    function beefIn (address _beefyVault, address _inputToken, uint256 _tokenInAmount, bytes calldata _token0, bytes calldata _token1) public {
        require(_tokenInAmount >= minimumAmount, 'Beefy: Insignificant input amount');
        require(IERC20(_inputToken).allowance(msg.sender, address(this)) >= _tokenInAmount, 'Beefy: Input token is not approved');

        IERC20(_inputToken).safeTransferFrom(msg.sender, address(this), _tokenInAmount);
        _swapAndStake(_beefyVault, _inputToken, _inputToken, _token0, _token1);
    }

    function beefOut (address _beefyVault, uint256 _withdrawAmount) external {
        address[] memory tokens = _beefOut(_beefyVault, _withdrawAmount);
         _returnAssets(tokens);
    }

    function beefOutAndSwap(address _beefyVault, uint256 _withdrawAmount, address _desiredToken, bytes calldata _dataToken0, bytes calldata _dataToken1) external {
        (IBeefyVault vault, IUniswapV2Pair pair, bool singleAsset) =  _getVaultPair(_beefyVault);
        vault.safeTransferFrom(msg.sender, address(this), _withdrawAmount);
        vault.withdraw(_withdrawAmount);

       if (!singleAsset) {
            _removeLiquidity(address(pair), address(this));

            address[] memory path = new address[](3);
            path[0] = pair.token0();
            path[1] = pair.token1();
            path[2] = _desiredToken;

            _approveTokenIfNeeded(path[0], address(oneInchRouter));
            _approveTokenIfNeeded(path[1], address(oneInchRouter));

            if (_desiredToken != path[0]) {
                _swapViaOneInch(path[0], _dataToken0);
            }

            if (_desiredToken != path[1]) {
                _swapViaOneInch(path[1], _dataToken1);
            }

            _returnAssets(path);
        } else {
            address[] memory path = new address[](2);
            path[0] = vault.want();
            path[1] = _desiredToken;

            _approveTokenIfNeeded(path[0], address(oneInchRouter));

            _swapViaOneInch(path[0], _dataToken0);

            _returnAssets(path);
        }
    }

    // Zap out funds from the 'fromMooVault', swap whats needed to swap and reinvest into the 'toMooVault'.
    function beefOutAndReInvest(address _fromMooVault, address _toMooVault, uint256 _mooTokenAmount, bytes calldata _token0ToFrom, bytes calldata _token1ToFrom) external {
        (IBeefyVault vault, IUniswapV2Pair pair, bool singleAsset) = _getVaultPair(_fromMooVault);
        (,,bool toSingleAsset) = _getVaultPair(_toMooVault);

        address token0; 
        address token1;
        if (!singleAsset) {
            _beefOut(_fromMooVault, _mooTokenAmount);
            token0 = pair.token0();
            token1 = pair.token1();
            if (!toSingleAsset) {
                _swapAndStake(_toMooVault, token0, token1, _token0ToFrom, _token1ToFrom);   
            } else {
                _swapAndStake(_toMooVault, token0, _token0ToFrom);
                _swapAndStake(_toMooVault, token1, _token1ToFrom);
            }
        } else {
            vault.safeTransferFrom(msg.sender, address(this), _mooTokenAmount);
            vault.withdraw(_mooTokenAmount);
            token0 = vault.want();
            token1 = token0;
            toSingleAsset ? _swapAndStake(_toMooVault, token0, _token0ToFrom) : _swapAndStake(_toMooVault, token0, token1, _token0ToFrom, _token1ToFrom);
        }
    }

    // View function helpers for the app
    // Since solidly stable pairs can be inbalanced we need the proper ratio for our swap, we need to accound both for price of the assets and the ratio of the pair. 
    function quoteStableAddLiquidityRatio(address _beefyVault) external view returns (uint256 ratio1to0) {
            (IBeefyVault vault, IUniswapV2Pair pairAddress,) = _getVaultPair(_beefyVault);
            ISolidlyPair pair = ISolidlyPair(address(pairAddress));
            address tokenA = pair.token0();
            address tokenB = pair.token1();

            uint256 investment = 1e18;
            uint out = pair.getAmountOut(investment, tokenA);
            ISolidlyRouter router = ISolidlyRouter(IStrategy(vault.strategy()).unirouter());
            (uint amountA, uint amountB,) = router.quoteAddLiquidity(tokenA, tokenB, pair.stable(), investment, out);
                
            amountA = amountA * 1e18 / 10**IERC20Extended(tokenA).decimals();
            amountB = amountB * 1e18 / 10**IERC20Extended(tokenB).decimals();
            out = out * 1e18 / 10**IERC20Extended(tokenB).decimals();
            investment = investment * 1e18 / 10**IERC20Extended(tokenA).decimals();
                
            uint ratio = out * 1e18 / investment * amountA / amountB; 
                
            return investment * 1e18 / (ratio + 1e18);
    }

    // quoting removing liquidity in uniswapv2 pairs requires us to know the fee rates of the pair, we use the data source to fetch this info and have an accurate estimate.
    function quoteRemoveLiquidity(IBeefyVault _beefyVault, uint256 _mooTokenAmt) external view returns (uint256 amt0, uint256 amt1, address token0, address token1) {
        uint256 withdrawFee = IStrategy(_beefyVault.strategy()).withdrawalFee();
        uint256 liquidity = _mooTokenAmt * _beefyVault.balance() / _beefyVault.totalSupply();
        uint256 fee = withdrawFee > 0 ? liquidity * withdrawFee / 10000 : 0;
        liquidity = liquidity - fee;
        
        (, IUniswapV2Pair pair,) = _getVaultPair(address(_beefyVault));
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

    // Internal functions

    function _beefOut (address _beefyVault, uint256 _withdrawAmount) private returns (address[] memory tokens) {
        (IBeefyVault vault, IUniswapV2Pair pair,) = _getVaultPair(_beefyVault);

        IERC20(_beefyVault).safeTransferFrom(msg.sender, address(this), _withdrawAmount);
        vault.withdraw(_withdrawAmount);

        _removeLiquidity(address(pair), address(this));

        tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();
    }

    function _removeLiquidity(address _pair, address _to) private {
        IERC20(_pair).safeTransfer(_pair, IERC20(_pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(_pair).burn(_to);

        require(amount0 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    
    // we measure the amount of extra lp is created after the pair claims fees before we are sent our tokens when removing liquidity
    function _mintFee(IUniswapV2Pair _pair, uint112 _reserve0, uint112 _reserve1, uint256 _totalSupply) private view returns (uint256 liquidity) {
        uint _kLast = _pair.kLast();
        address factory =  _pair.factory();
        (uint rootKInteger, uint rootKLastInteger) = dataSource.feeData(factory);
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0) * _reserve1);
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = _totalSupply * (rootK - rootKLast) * rootKLastInteger;
                    uint denominator = rootK * rootKInteger + (rootKLast * rootKLastInteger);
                    liquidity = numerator / denominator;
                }
            }
    }

    function _getVaultPair (address _beefyVault) private view returns (IBeefyVault vault, IUniswapV2Pair pair, bool singleAsset) {
        vault = IBeefyVault(_beefyVault);

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

    // helper function for us to determine whether the pair is a solidly type and whether or not its a stable.
    function _getSolidType (address _pair) private view returns (bool isSolidPair, bool stable) {
        ISolidlyPair solidPair = ISolidlyPair(_pair);
        address factory = solidPair.factory();
        isSolidPair = dataSource.isSolidPair(factory);
        stable = isSolidPair ? solidPair.stable() : false;
    }

    function _swapAndStake(address _vault, address _inputToken, bytes calldata _token0) private {
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
  

    function _swapAndStake(address _beefyVault, address _inputToken0, address _inputToken1, bytes calldata _token0, bytes calldata _token1) private {
        (IBeefyVault vault, IUniswapV2Pair pair, bool singleAsset) =  _getVaultPair(_beefyVault);

        if (!singleAsset) {
            address[] memory path;
            if (_inputToken0 == _inputToken1) {
                path = new address[](3);
                path[0] = pair.token0();
                path[1] = pair.token1();
                path[2] = _inputToken0;
            } else {
                path = new address[](4);
                path[0] = pair.token0();
                path[1] = pair.token1();
                path[2] = _inputToken0;
                path[3] = _inputToken1;
            }

            if (_inputToken0 != path[0]) {
                _swapViaOneInch(_inputToken0, _token0);
            }

            if (_inputToken1 != path[1]) {
                _swapViaOneInch(_inputToken1, _token1);
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
            _swapAndStake(_beefyVault, _inputToken0, _token0);
        }
    }

    // our main swap function call. we call the aggregator contract with our fed data. if we get an error we revert and return the error result. 
    function _swapViaOneInch(address _inputToken, bytes memory _callData) private returns (uint) {
        
        _approveTokenIfNeeded(_inputToken, address(oneInchRouter));

        (bool success, bytes memory retData) = oneInchRouter.call(_callData);

        propagateError(success, retData, "1inch");

        require(success == true, "calling 1inch got an error");
        (uint actualAmount, ) = abi.decode(retData, (uint, uint));
        return actualAmount;
    }

    function _returnAssets(address[] memory _tokens) private {
        uint256 balance;
        for (uint256 i; i < _tokens.length; i++) {
            balance = IERC20(_tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                if (_tokens[i] == WETH) {
                    IWETH(WETH).withdraw(balance);
                    (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                    require(success, 'Beefy: ETH transfer failed');
                } else {
                    IERC20(_tokens[i]).safeTransfer(msg.sender, balance);
                }
            }
        }
    }

    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint).max);
        }
    }

    // Our only setter function in case the data source needs to be upgraded. 

    function setDataSource(address _dataSource) external onlyOwner {
        dataSource = IBeefyDataSource(_dataSource);
    }

    // Error reporting from our call to the aggrator contract when we try to swap. 
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

    receive() external payable {
        assert(msg.sender == WETH);
    }
}