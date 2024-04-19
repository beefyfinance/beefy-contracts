// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IBeefyOracle } from "../interfaces/oracle/IBeefyOracle.sol";
import { IBeefyZapRouter } from "../interfaces/beefy/IBeefyZapRouter.sol";

/// @title Beefy Swapper
/// @author Beefy, @kexley
/// @notice Centralized swapper
contract BeefySwapper is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    /// @dev Price update failed for a token
    /// @param token Address of token that failed the price update
    error PriceFailed(address token);

    /// @dev No swap data has been set by the owner
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    error NoSwapData(address fromToken, address toToken);

    /// @dev Not enough output was returned from the swap
    /// @param amountOut Amount returned by the swap
    /// @param minAmountOut Minimum amount required from the swap
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);

    /// @dev Caller is not owner or manager
    error NotManager();

    /// @notice Stored swap steps for a token
    mapping(address => mapping(address => mapping(address => IBeefyZapRouter.Step[]))) public swapSteps;

    /// @notice Oracle used to calculate the minimum output of a swap
    IBeefyOracle public oracle;

    /// @notice Minimum acceptable percentage slippage output in 18 decimals
    uint256 public slippage;

    /// @notice Manager of this contract
    address public keeper;

    /// @notice Zap contract used to swap tokens
    address public zap;

    /// @notice Zap token manager that handles token approvals
    address public zapTokenManager;

    /// @notice Swap between two tokens
    /// @param caller Address of the caller of the swap
    /// @param fromToken Address of the source token
    /// @param toToken Address of the destination token
    /// @param amountIn Amount of source token inputted to the swap
    /// @param amountOut Amount of destination token outputted from the swap
    event Swap(
        address indexed caller,
        address indexed fromToken,
        address indexed toToken,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @notice Set new swap steps for the route between two tokens
    /// @param fromToken Address of the source token
    /// @param toToken Address of the destination token
    /// @param swapSteps Steps for swapping a pair of tokens
    event SetSwapSteps(
        address indexed caller,
        address indexed fromToken,
        address indexed toToken,
        IBeefyZapRouter.Step[] swapSteps
    );

    /// @notice Set a new oracle
    /// @param oracle New oracle address
    event SetOracle(address oracle);

    /// @notice Set a new slippage
    /// @param slippage New slippage amount
    event SetSlippage(uint256 slippage);

    /// @notice Set a new manager
    /// @param keeper New manager address
    event SetKeeper(address keeper);

    /// @notice Set a new zap
    /// @param zap New zap address
    /// @param zapTokenManager New zap token manager address
    event SetZap(address zap, address zapTokenManager);

    modifier onlyManager {
        if (!_isCallerManager()) revert NotManager();
        _;
    }

    /// @dev Internal function to check if caller is manager
    function _isCallerManager() internal view returns (bool isManager) {
        if (msg.sender == owner() || msg.sender == keeper) isManager = true;
    }

    /// @notice Initialize the contract
    /// @dev Ownership is transferred to msg.sender
    /// @param _zap Zap contract used to swap tokens
    /// @param _oracle Oracle to find prices for tokens
    /// @param _slippage Acceptable slippage for any swap
    /// @param _keeper Address of the manager
    function initialize(address _zap, address _oracle, uint256 _slippage, address _keeper) external initializer {
        __Ownable_init();
        zap = _zap;
        oracle = IBeefyOracle(_oracle);
        slippage = _slippage;
        keeper = _keeper;
        zapTokenManager = IBeefyZapRouter(_zap).tokenManager();
    }

    /// @notice Swap between two tokens with slippage calculated using the oracle
    /// @dev Caller must have already approved this contract to spend the _fromToken. After the
    /// swap the _toToken token is sent directly to the caller
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @return amountOut Amount of _toToken returned to the caller
    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) external returns (uint256 amountOut) {
        uint256 minAmountOut = _getAmountOut(_fromToken, _toToken, _amountIn);
        amountOut = _swap(_fromToken, _toToken, _amountIn, minAmountOut);
    }

    /// @notice Swap between two tokens with slippage provided by the caller
    /// @dev Caller must have already approved this contract to spend the _fromToken. After the
    /// swap the _toToken token is sent directly to the caller
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @param _minAmountOut Minimum amount of _toToken that is acceptable to be returned to caller
    /// @return amountOut Amount of _toToken returned to the caller
    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256 amountOut) {
        amountOut = _swap(_fromToken, _toToken, _amountIn, _minAmountOut);
    }

    /// @notice Get the amount out from a simulated swap with slippage and non-fresh prices
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @return amountOut Amount of _toTokens returned from the swap
    function getAmountOut(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) external view returns (uint256 amountOut) {
        (uint256 fromPrice, uint256 toPrice) = 
            (oracle.getPrice(msg.sender, _fromToken), oracle.getPrice(msg.sender, _toToken));
        uint8 decimals0 = IERC20MetadataUpgradeable(_fromToken).decimals();
        uint8 decimals1 = IERC20MetadataUpgradeable(_toToken).decimals();
        amountOut = _calculateAmountOut(_amountIn, fromPrice, toPrice, decimals0, decimals1);
    }

    /// @notice Get the swap steps between two tokens, if a default is not set then use strategy 
    /// specific routing
    /// @param _caller The address that wants to swap tokens
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @return steps Swap steps between the two tokens
    function getSwapSteps(
        address _caller,
        address _fromToken,
        address _toToken
    ) public view returns (IBeefyZapRouter.Step[] memory steps) {
        steps = swapSteps[address(0)][_fromToken][_toToken].length != 0 
            ? swapSteps[address(0)][_fromToken][_toToken]
            : swapSteps[_caller][_fromToken][_toToken];
    }

    /// @dev Use the oracle to get prices for both _fromToken and _toToken and calculate the
    /// estimated output reduced by the slippage
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @return amountOut Amount of _toToken returned by the swap
    function _getAmountOut(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) private returns (uint256 amountOut) {
        (uint256 fromPrice, uint256 toPrice) = _getFreshPrice(_fromToken, _toToken);
        uint8 decimals0 = IERC20MetadataUpgradeable(_fromToken).decimals();
        uint8 decimals1 = IERC20MetadataUpgradeable(_toToken).decimals();
        uint256 slippedAmountIn = _amountIn * slippage / 1 ether;
        amountOut = _calculateAmountOut(slippedAmountIn, fromPrice, toPrice, decimals0, decimals1);
    }

    /// @dev _fromToken is pulled into this contract from the caller, swap is executed according to
    /// the stored data, resulting _toTokens are sent to the caller
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @param _minAmountOut Minimum amount of _toToken that is acceptable to be returned to caller
    /// @return amountOut Amount of _toToken returned to the caller
    function _swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) private returns (uint256 amountOut) {
        IERC20MetadataUpgradeable(_fromToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        _executeSwap(_fromToken, _toToken, _amountIn, _minAmountOut);
        amountOut = IERC20MetadataUpgradeable(_toToken).balanceOf(address(this));
        if (amountOut < _minAmountOut) revert SlippageExceeded(amountOut, _minAmountOut);
        IERC20MetadataUpgradeable(_toToken).safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, _fromToken, _toToken, _amountIn, amountOut);
    }

    /// @dev Use the stored steps for the tokens and zap
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @param _minAmountOut Minimum amount of _toToken that is acceptable to be returned to caller
    function _executeSwap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) private {
        IBeefyZapRouter.Step[] memory steps = getSwapSteps(msg.sender, _fromToken, _toToken);
        if (steps.length == 0) revert NoSwapData(_fromToken, _toToken);

        IBeefyZapRouter.Input[] memory inputs = new IBeefyZapRouter.Input[](1);
        IBeefyZapRouter.Output[] memory outputs = new IBeefyZapRouter.Output[](1);
        inputs[0] = IBeefyZapRouter.Input(_fromToken, _amountIn);
        outputs[0] = IBeefyZapRouter.Output(_toToken, _minAmountOut);

        IBeefyZapRouter.Order memory order = IBeefyZapRouter.Order({
            inputs: inputs,
            outputs: outputs,
            relay: IBeefyZapRouter.Relay(address(0), 0, ''),
            user: address(this),
            recipient: address(this)
        });

        IERC20MetadataUpgradeable(_fromToken).forceApprove(zapTokenManager, type(uint256).max);
        IBeefyZapRouter(zap).executeOrder(order, steps);
    }

    /// @dev Fetch fresh prices from the oracle
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @return fromPrice Price of token to swap from
    /// @return toPrice Price of token to swap to
    function _getFreshPrice(
        address _fromToken,
        address _toToken
    ) private returns (uint256 fromPrice, uint256 toPrice) {
        bool success;
        (fromPrice, success) = oracle.getFreshPrice(msg.sender, _fromToken);
        if (!success) revert PriceFailed(_fromToken);
        (toPrice, success) = oracle.getFreshPrice(msg.sender, _toToken);
        if (!success) revert PriceFailed(_toToken);
    }

    /// @dev Calculate the amount out given the prices and the decimals of the tokens involved
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @param _price0 Price of the _fromToken
    /// @param _price1 Price of the _toToken
    /// @param _decimals0 Decimals of the _fromToken
    /// @param _decimals1 Decimals of the _toToken
    function _calculateAmountOut(
        uint256 _amountIn,
        uint256 _price0,
        uint256 _price1,
        uint8 _decimals0,
        uint8 _decimals1
    ) private pure returns (uint256 amountOut) {
        amountOut = _amountIn * (_price0 * 10 ** _decimals1) / (_price1 * 10 ** _decimals0);
    }

    /// @notice Set multiple stored swap steps for the routes between two tokens
    /// @dev No validation checks
    /// @param _fromTokens Tokens to swap from
    /// @param _toTokens Tokens to swap to
    /// @param _swapSteps Swap steps to store
    function setSwapSteps(
        address[] calldata _fromTokens,
        address[] calldata _toTokens,
        IBeefyZapRouter.Step[][] calldata _swapSteps
    ) external {
        bool isManager = _isCallerManager();
        for (uint i; i < _fromTokens.length; ++i) {
            _setSwapSteps(_fromTokens[i], _toTokens[i], _swapSteps[i], isManager);
        }
    }

    /// @dev Set or change the stored swap steps for the route between two tokens
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _swapSteps Swap steps to store
    /// @param _isManager Caller is a manager or not
    function _setSwapSteps(
        address _fromToken,
        address _toToken,
        IBeefyZapRouter.Step[] calldata _swapSteps,
        bool _isManager
    ) internal {
        address caller = _isManager ? address(0) : msg.sender;
        delete swapSteps[caller][_fromToken][_toToken];
        for (uint i; i < _swapSteps.length; ++i) {
            swapSteps[caller][_fromToken][_toToken].push(_swapSteps[i]);
        }
        emit SetSwapSteps(caller, _fromToken, _toToken, _swapSteps);
    }

    /* ----------------------------------- OWNER FUNCTIONS ----------------------------------- */

    /// @notice Owner function to set the oracle used to calculate the minimum outputs
    /// @dev No validation checks
    /// @param _oracle Address of the new oracle
    function setOracle(address _oracle) external onlyOwner {
        oracle = IBeefyOracle(_oracle);
        emit SetOracle(_oracle);
    }

    /// @notice Owner function to set the slippage
    /// @param _slippage Acceptable slippage level
    function setSlippage(uint256 _slippage) external onlyOwner {
        if (_slippage > 1 ether) _slippage = 1 ether;
        slippage = _slippage;
        emit SetSlippage(_slippage);
    }

    /// @notice Owner function to set the keeper
    /// @param _keeper New manager address
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
        emit SetKeeper(_keeper);
    }

    /// @notice Owner function to set the zap
    /// @param _zap New manager address
    function setZap(address _zap) external onlyOwner {
        zap = _zap;
        zapTokenManager = IBeefyZapRouter(_zap).tokenManager();
        emit SetZap(_zap, zapTokenManager);
    }
}
