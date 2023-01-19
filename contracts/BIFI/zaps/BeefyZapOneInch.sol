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


// Aggregator Zap compatible with all single asset, uniswapv2, and solidly router Beefy Vaults. 
contract BeefyZapOneInch {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVault;

    // needed addresses for zap 
    address public immutable oneInchRouter;
    address public immutable WETH;
    uint256 public constant minimumAmount = 1000;

    enum WantType {
        WANT_TYPE_SINGLE,
        WANT_TYPE_UNISWAP_V2,
        WANT_TYPE_SOLIDLY_STABLE,
        WANT_TYPE_SOLIDLY_VOLATILE
    }

    event TokenReturned(address token, uint256 amount);
    event ZapIn(address vault, address tokenIn, uint256 amountIn);
    event ZapOut(address vault, address desiredToken, uint256 mooTokenIn);

    constructor(address _oneInchRouter, address _WETH) {
        // Safety checks to ensure WETH token address
        IWETH(_WETH).deposit{value: 0}();
        IWETH(_WETH).withdraw(0);
        WETH = _WETH;

        oneInchRouter = _oneInchRouter;
    }

    // Zap's main functions external and public functions
    function beefInETH (address _beefyVault, bytes calldata _token0, bytes calldata _token1, WantType _type) external payable {
        require(msg.value >= minimumAmount, 'Beefy: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();
        _swapAndStake(_beefyVault, WETH, WETH, _token0, _token1, _type);
        emit ZapIn(_beefyVault, WETH, msg.value);
    }

    function beefIn (address _beefyVault, address _inputToken, uint256 _tokenInAmount, bytes calldata _token0, bytes calldata _token1, WantType _type) public {
        require(_tokenInAmount >= minimumAmount, 'Beefy: Insignificant input amount');

        IERC20(_inputToken).safeTransferFrom(msg.sender, address(this), _tokenInAmount);
        _swapAndStake(_beefyVault, _inputToken, _inputToken, _token0, _token1, _type);
        emit ZapIn(_beefyVault,  _inputToken, _tokenInAmount);
    }

    function beefOut (address _beefyVault, uint256 _withdrawAmount) external {
        address[] memory tokens = _beefOut(_beefyVault, _withdrawAmount);
         _returnAssets(tokens);
    }

    function beefOutAndSwap(address _beefyVault, uint256 _withdrawAmount, address _desiredToken, bytes calldata _dataToken0, bytes calldata _dataToken1, WantType _type) external {
        (IBeefyVault vault, IUniswapV2Pair pair) =  _getVaultPair(_beefyVault);
        vault.safeTransferFrom(msg.sender, address(this), _withdrawAmount);
        vault.withdraw(_withdrawAmount);
         emit ZapOut(_beefyVault, _desiredToken, _withdrawAmount);

       if (_type != WantType.WANT_TYPE_SINGLE) {
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
    function beefOutAndReInvest(
        address _fromMooVault, 
        address _toMooVault, 
        uint256 _mooTokenAmount, 
        bytes calldata _token0ToFrom, 
        bytes calldata _token1ToFrom, 
        WantType _fromType, 
        WantType _toType
    ) external {
        (IBeefyVault vault, IUniswapV2Pair pair) = _getVaultPair(_fromMooVault);

        address token0; 
        address token1;
        if (_fromType != WantType.WANT_TYPE_SINGLE) {
            _beefOut(_fromMooVault, _mooTokenAmount);
            token0 = pair.token0();
            token1 = pair.token1();
            if (_toType != WantType.WANT_TYPE_SINGLE) {
                _swapAndStake(_toMooVault, token0, token1, _token0ToFrom, _token1ToFrom, _toType);   
            } else {
                _swapAndStake(_toMooVault, token0, _token0ToFrom);
                _swapAndStake(_toMooVault, token1, _token1ToFrom);
            }
        } else {
            vault.safeTransferFrom(msg.sender, address(this), _mooTokenAmount);
            vault.withdraw(_mooTokenAmount);
            token0 = vault.want();
            token1 = token0;
            _toType == WantType.WANT_TYPE_SINGLE ? _swapAndStake(_toMooVault, token0, _token0ToFrom) : _swapAndStake(_toMooVault, token0, token1, _token0ToFrom, _token1ToFrom, _toType);
        }
    }

    // View function helpers for the app
    // Since solidly stable pairs can be inbalanced we need the proper ratio for our swap, we need to accound both for price of the assets and the ratio of the pair. 
    function quoteStableAddLiquidityRatio(address _beefyVault) external view returns (uint256 ratio1to0) {
            (IBeefyVault vault, IUniswapV2Pair pairAddress) = _getVaultPair(_beefyVault);
            ISolidlyPair pair = ISolidlyPair(address(pairAddress));
            address tokenA = pair.token0();
            address tokenB = pair.token1();

            uint256 investment = IERC20(tokenA).balanceOf(address(pair)) * 10 / 10000;
            uint out = pair.getAmountOut(investment, tokenA);
            ISolidlyRouter router = ISolidlyRouter(IStrategy(vault.strategy()).unirouter());
            (uint amountA, uint amountB,) = router.quoteAddLiquidity(tokenA, tokenB, pair.stable(), investment, out);
                
            amountA = amountA * 1e18 / 10**IERC20Extended(tokenA).decimals();
            amountB = amountB * 1e18 / 10**IERC20Extended(tokenB).decimals();
            out = out * 1e18 / 10**IERC20Extended(tokenB).decimals();
            investment = investment * 1e18 / 10**IERC20Extended(tokenA).decimals();
                
            uint ratio = out * 1e18 / investment * amountA / amountB; 
                
            return 1e18 * 1e18 / (ratio + 1e18);
    }

    // Internal functions
    function _beefOut (address _beefyVault, uint256 _withdrawAmount) private returns (address[] memory tokens) {
        (IBeefyVault vault, IUniswapV2Pair pair) = _getVaultPair(_beefyVault);

        IERC20(_beefyVault).safeTransferFrom(msg.sender, address(this), _withdrawAmount);
        vault.withdraw(_withdrawAmount);

        _removeLiquidity(address(pair), address(this));

        tokens = new address[](2);
        tokens[0] = pair.token0();
        tokens[1] = pair.token1();
        
        emit ZapOut(_beefyVault, address(pair), _withdrawAmount);
    }

    function _removeLiquidity(address _pair, address _to) private {
        IERC20(_pair).safeTransfer(_pair, IERC20(_pair).balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = IUniswapV2Pair(_pair).burn(_to);

        require(amount0 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amount1 >= minimumAmount, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    function _getVaultPair (address _beefyVault) private pure returns (IBeefyVault vault, IUniswapV2Pair pair) {
        vault = IBeefyVault(_beefyVault);

        try vault.want() returns (address pairAddress) {
            pair = IUniswapV2Pair(pairAddress); // Vault V6
        } catch {
            pair = IUniswapV2Pair(vault.token()); // Vault V5
        }
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
  

    function _swapAndStake(address _beefyVault, address _inputToken0, address _inputToken1, bytes calldata _token0, bytes calldata _token1, WantType _type) private {
        (IBeefyVault vault, IUniswapV2Pair pair) =  _getVaultPair(_beefyVault);

        if (_type != WantType.WANT_TYPE_SINGLE) {
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

            _approveTokenIfNeeded(path[0], address(router));
            _approveTokenIfNeeded(path[1], address(router));
            uint256 lp0Amt = IERC20(path[0]).balanceOf(address(this));
            uint256 lp1Amt = IERC20(path[1]).balanceOf(address(this));

            uint256 amountLiquidity;
            if (_type == WantType.WANT_TYPE_SOLIDLY_STABLE || _type == WantType.WANT_TYPE_SOLIDLY_VOLATILE) {
                 bool stable = _type == WantType.WANT_TYPE_SOLIDLY_STABLE ? true : false;
                (,, amountLiquidity) = ISolidlyRouter(router)
                .addLiquidity(path[0], path[1], stable,  lp0Amt, lp1Amt, 1, 1, address(this), block.timestamp);
            } else {
                (,, amountLiquidity) = IUniswapRouterETH(router)
                .addLiquidity(path[0], path[1], lp0Amt, lp1Amt, 1, 1, address(this), block.timestamp);
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
    function _swapViaOneInch(address _inputToken, bytes memory _callData) private {
        
        _approveTokenIfNeeded(_inputToken, address(oneInchRouter));

        (bool success, bytes memory retData) = oneInchRouter.call(_callData);

        propagateError(success, retData, "1inch");

        require(success == true, "calling 1inch got an error");
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
                    emit TokenReturned(_tokens[i], balance);
                } else {
                    IERC20(_tokens[i]).safeTransfer(msg.sender, balance);
                    emit TokenReturned(_tokens[i], balance);
                }
            }
        }
    }

    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint).max);
        }
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