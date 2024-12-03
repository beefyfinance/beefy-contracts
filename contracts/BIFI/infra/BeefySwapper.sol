// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {BytesLib} from "../utils/BytesLib.sol";
import {IBeefyOracle} from "../interfaces/oracle/IBeefyOracle.sol";
import {IBeefySwapper} from "../interfaces/beefy/IBeefySwapper.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @title Beefy Swapper
/// @author Beefy, @kexley
/// @notice Centralized swapper
contract BeefySwapper is OwnableUpgradeable, IBeefySwapper {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using BytesLib for bytes;

    /// @dev Price update failed for a token
    /// @param token Address of token that failed the price update
    error PriceFailed(address token);

    /// @dev No swap data has been set by the owner
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    error NoSwapData(address fromToken, address toToken);

    /// @dev Swap call failed
    /// @param router Target address of the failed swap call
    /// @param data Payload of the failed call
    error SwapFailed(address router, bytes data);

    /// @dev Not enough output was returned from the swap
    /// @param amountOut Amount returned by the swap
    /// @param minAmountOut Minimum amount required from the swap
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);

    /// @dev At least minLength tokens should be included in the route
    error RouteTooShort(uint256 minLength);

    /// @inheritdoc IBeefySwapper
    mapping(address => mapping(address => SwapInfo)) public swapInfo;

    /// @inheritdoc IBeefySwapper
    mapping(address => mapping(address => address[])) public swapRoute;

    /// @notice Oracle used to calculate the minimum output of a swap
    IBeefyOracle public oracle;

    /// @notice Minimum acceptable percentage slippage output in 18 decimals
    uint256 public slippage;

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

    /// @notice Set new swap info for the route between two tokens
    /// @param fromToken Address of the source token
    /// @param toToken Address of the destination token
    /// @param swapInfo Struct of stored swap information for the pair of tokens
    event SetSwapInfo(address indexed fromToken, address indexed toToken, SwapInfo swapInfo);

    /// @notice Set new swap route between two tokens
    /// @param fromToken Address of the source token
    /// @param toToken Address of the destination token
    /// @param route Array of tokens to route through
    event SetSwapRoute(address indexed fromToken, address indexed toToken, address[] route);

    /// @notice Set a new oracle
    /// @param oracle New oracle address
    event SetOracle(address oracle);

    /// @notice Set a new slippage
    /// @param slippage New slippage amount
    event SetSlippage(uint256 slippage);

    /// @notice Initialize the contract
    /// @dev Ownership is transferred to msg.sender
    /// @param _oracle Oracle to find prices for tokens
    /// @param _slippage Acceptable slippage for any swap
    function initialize(address _oracle, uint256 _slippage) external initializer {
        __Ownable_init();
        oracle = IBeefyOracle(_oracle);
        slippage = _slippage;
    }

    /// @inheritdoc IBeefySwapper
    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) external returns (uint256 amountOut) {
        uint256 minAmountOut = _getAmountOut(_fromToken, _toToken, _amountIn);
        amountOut = _swap(_fromToken, _toToken, _amountIn, minAmountOut);
    }

    /// @inheritdoc IBeefySwapper
    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256 amountOut) {
        amountOut = _swap(_fromToken, _toToken, _amountIn, _minAmountOut);
    }

    /// @inheritdoc IBeefySwapper
    function swap(
        address[] calldata _route,
        uint256 _amountIn
    ) external returns (uint256 amountOut) {
        uint256 minAmountOut = _getAmountOut(_route[0], _route[_route.length - 1], _amountIn);
        amountOut = _swap(_route, _amountIn, minAmountOut);
    }

    /// @inheritdoc IBeefySwapper
    function swap(
        address[] calldata _route,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256 amountOut) {
        amountOut = _swap(_route, _amountIn, _minAmountOut);
    }

    /// @inheritdoc IBeefySwapper
    function getAmountOut(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) external view returns (uint256 amountOut) {
        (uint256 fromPrice, uint256 toPrice) =
        (oracle.getPrice(_fromToken), oracle.getPrice(_toToken));
        uint8 decimals0 = IERC20MetadataUpgradeable(_fromToken).decimals();
        uint8 decimals1 = IERC20MetadataUpgradeable(_toToken).decimals();
        amountOut = _calculateAmountOut(_amountIn, fromPrice, toPrice, decimals0, decimals1);
    }

    /// @inheritdoc IBeefySwapper
    function hasSwap(
        address _fromToken,
        address _toToken
    ) external view returns (bool) {
        if (_haveSwapData(_fromToken, _toToken)) {
            return true;
        }

        return swapRoute[_fromToken][_toToken].length > 0;
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
    /// Will attempt direct swap first, if no data is stored for the pair, will attempt to swap via stored route
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
        if (!_haveSwapData(_fromToken, _toToken)) {
            address[] memory route = swapRoute[_fromToken][_toToken];
            if (route.length == 0) {
                revert NoSwapData(_fromToken, _toToken);
            }
            return _swap(route, _amountIn, _minAmountOut);
        }

        {
            IERC20MetadataUpgradeable(_fromToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            amountOut = IERC20MetadataUpgradeable(_fromToken).balanceOf(address(this));

            _executeSwap(_fromToken, _toToken, amountOut, _minAmountOut);
            amountOut = IERC20MetadataUpgradeable(_toToken).balanceOf(address(this));

            if (amountOut < _minAmountOut) {
                revert SlippageExceeded(amountOut, _minAmountOut);
            }

            IERC20MetadataUpgradeable(_toToken).safeTransfer(msg.sender, amountOut);
            emit Swap(msg.sender, _fromToken, _toToken, _amountIn, amountOut);
        }
    }

    /// @dev _route[0] is pulled into this contract from the caller, swap is executed according to
    /// the stored data, resulting _route[_route.length-1] are sent to the caller
    /// @param _route List of tokens to swap via
    /// @param _amountIn Amount of _route[0] to use in the swap
    /// @param _minAmountOut Minimum amount of _route[_route.length-1] that is acceptable to be returned to caller
    /// @return amountOut Amount of _route[_route.length-1] returned to the caller
    function _swap(
        address[] memory _route,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) private returns (uint256 amountOut) {
        uint256 routeLength = _route.length;
        if (routeLength < 2) {
            revert RouteTooShort(2);
        }
        uint256 lastIndex = routeLength - 1;
        address fromToken = _route[0];
        address toToken = _route[lastIndex];

        IERC20MetadataUpgradeable(fromToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        amountOut = IERC20MetadataUpgradeable(fromToken).balanceOf(address(this));

        uint256 nextIndex;
        address nextToken;
        for (uint i; i < lastIndex;) {
            nextIndex = i + 1;
            nextToken = _route[nextIndex];
            _executeSwap(_route[i], nextToken, amountOut, nextIndex == lastIndex ? _minAmountOut : 0);
            amountOut = IERC20MetadataUpgradeable(nextToken).balanceOf(address(this));
            unchecked {++i;}
        }

        if (amountOut < _minAmountOut) {
            revert SlippageExceeded(amountOut, _minAmountOut);
        }

        IERC20MetadataUpgradeable(toToken).safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, fromToken, toToken, _amountIn, amountOut);
    }

    /// @dev Fetch the stored swap info for the route between the two tokens, insert the encoded
    /// balance and minimum output to the payload and call the stored router with the data
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
        SwapInfo memory swapData = swapInfo[_fromToken][_toToken];
        address router = swapData.router;
        bytes memory data = swapData.data;

        data = _insertData(data, swapData.amountIndex, abi.encode(_amountIn));

        bytes memory minAmountData = swapData.minAmountSign >= 0
            ? abi.encode(_minAmountOut)
            : abi.encode(- int256(_minAmountOut));

        data = _insertData(data, swapData.minIndex, minAmountData);

        IERC20MetadataUpgradeable(_fromToken).forceApprove(router, type(uint256).max);
        (bool success,) = router.call(data);
        if (!success) revert SwapFailed(router, data);
    }

    /// @dev Helper function to check if there is swap data defined for a token pair
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @return haveData Whether there is swap data defined
    function _haveSwapData(address _fromToken, address _toToken) private view returns (bool haveData) {
        haveData = swapInfo[_fromToken][_toToken].router != address(0);
    }

    /// @dev Helper function to insert data to an in-memory bytes string
    /// @param _data Template swap payload with blank spaces to overwrite
    /// @param _index Start location in the data byte string where the _newData should overwrite
    /// @param _newData New data that is to be inserted
    /// @return data The resulting string from the insertion
    function _insertData(
        bytes memory _data,
        uint256 _index,
        bytes memory _newData
    ) private pure returns (bytes memory data) {
        data = bytes.concat(
            bytes.concat(
                _data.slice(0, _index),
                _newData
            ),
            _data.slice(_index + 32, _data.length - (_index + 32))
        );
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
        (fromPrice, success) = oracle.getFreshPrice(_fromToken);
        if (!success) revert PriceFailed(_fromToken);
        (toPrice, success) = oracle.getFreshPrice(_toToken);
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

    /* ----------------------------------- OWNER FUNCTIONS ----------------------------------- */

    /// @notice Owner function to set the stored swap info for the route between two tokens
    /// @dev No validation checks
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _swapInfo Swap info to store
    function setSwapInfo(
        address _fromToken,
        address _toToken,
        SwapInfo calldata _swapInfo
    ) external onlyOwner {
        swapInfo[_fromToken][_toToken] = _swapInfo;
        emit SetSwapInfo(_fromToken, _toToken, _swapInfo);
    }

    /// @notice Owner function to set multiple stored swap info for the routes between two tokens
    /// @dev No validation checks
    /// @param _fromTokens Tokens to swap from
    /// @param _toTokens Tokens to swap to
    /// @param _swapInfos Swap infos to store
    function setSwapInfos(
        address[] calldata _fromTokens,
        address[] calldata _toTokens,
        SwapInfo[] calldata _swapInfos
    ) external onlyOwner {
        uint256 tokenLength = _fromTokens.length;
        for (uint i; i < tokenLength;) {
            swapInfo[_fromTokens[i]][_toTokens[i]] = _swapInfos[i];
            emit SetSwapInfo(_fromTokens[i], _toTokens[i], _swapInfos[i]);
            unchecked {++i;}
        }
    }

    /// @notice Owner function to set the stored swap route between two tokens
    /// @dev Oracle for input and output tokens, and swap data for each token pair must be valid
    /// @param _route Array of tokens to route through
    function setSwapRoute(address[] calldata _route) external onlyOwner {
        uint256 routeLength = _route.length;
        if (routeLength < 3) {
            revert RouteTooShort(3);
        }

        address fromToken = _route[0];
        uint256 lastIndex = routeLength - 1;
        address toToken = _route[lastIndex];

        // check if we have functioning oracle for first and last tokens
        _getFreshPrice(fromToken, toToken);

        // check we can swap between each pair of tokens in the route
        for (uint i; i < lastIndex;) {
            if (!_haveSwapData(_route[i], _route[i + 1])) {
                revert NoSwapData(_route[i], _route[i + 1]);
            }
            unchecked {++i;}
        }

        swapRoute[fromToken][toToken] = _route;
        emit SetSwapRoute(fromToken, toToken, _route);
    }

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
}
