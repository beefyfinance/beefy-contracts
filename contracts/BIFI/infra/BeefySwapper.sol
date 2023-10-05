// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IBeefyOracle } from "../interfaces/oracle/IBeefyOracle.sol";
import { BytesLib } from "../utils/BytesLib.sol";

/// @title Beefy Swapper
/// @author Beefy, @kexley
/// @notice Centralized swapper for strategies
contract BeefySwapper is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;
    using BytesLib for bytes;

    /// @dev Price update failed for a token
    /// @param token Address of token that failed the price update
    error PriceFailed(address token);

    /// @dev Swap call failed
    /// @param router Target address of the failed swap call
    /// @param data Payload of the failed call
    error SwapFailed(address router, bytes data);

    /// @dev Stored data for a swap
    /// @param router Target address that will handle the swap
    /// @param data Payload of a template swap between the two tokens
    /// @param amountIndex Location in the data byte string where the amount should be overwritten
    /// @param minIndex Location in the data byte string where the min amount to swap should be
    /// overwritten
    /// @param minAmountSign Represents the sign of the min amount to be included in the swap, any
    /// negative value will encode a negative min amount (required for Balancer)
    struct SwapInfo {
        address router;
        bytes data;
        uint256 amountIndex;
        uint256 minIndex;
        int8 minAmountSign;
    }

    /// @notice Stored swap info for a token
    mapping(address => mapping(address => SwapInfo)) public swapInfo;

    /// @notice Oracle used to calculate the minimum output of a swap
    IBeefyOracle public oracle;

    /// @notice Minimum acceptable percentage slippage output in 18 decimals
    uint256 public slippage;

    /// @notice Set new swap info for the route between two tokens
    event SetSwapInfo(address indexed fromToken, address indexed toToken, SwapInfo swapInfo);

    /// @notice Set a new oracle
    event SetOracle(address oracle);

    /// @notice Initialize the contract
    /// @dev Ownership is transferred to msg.sender
    function initialize() external initializer {
        __Ownable_init();
    }

    /// @notice Swap between two tokens with slippage calculated using the oracle
    /// @dev Caller must have already approved this contract to spend the _fromToken. After the
    /// swap the _toToken token is sent directly to the caller
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amount Amount of _fromToken to use in the swap
    /// @return outputAmount Amount of _toToken returned to the caller
    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amount
    ) external returns (uint256 outputAmount) {
        uint256 minAmountOut = _getMinAmount(_fromToken, _toToken, _amount);
        outputAmount = _swap(_fromToken, _toToken, _amount, minAmountOut);
    }

    /// @notice Swap between two tokens with slippage provided by the caller
    /// @dev Caller must have already approved this contract to spend the _fromToken. After the
    /// swap the _toToken token is sent directly to the caller
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amount Amount of _fromToken to use in the swap
    /// @param _minAmountOut Minimum amount of _toToken that is acceptable to be returned to caller
    /// @return outputAmount Amount of _toToken returned to the caller
    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        uint256 _minAmountOut
    ) external returns (uint256 outputAmount) {
        outputAmount = _swap(_fromToken, _toToken, _amount, _minAmountOut);
    }

    /// @dev Use the oracle to get prices for both _fromToken and _toToken and calculate the
    /// estimated output reduced by the slippage
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amount Amount of _fromToken to use in the swap
    /// @return minAmountOut Minimum amount of _toToken that is acceptable to be returned to caller
    function _getMinAmount(
        address _fromToken,
        address _toToken,
        uint256 _amount
    ) private returns (uint256 minAmountOut) {
        address[] memory tokens = new address[](2);
        (tokens[0], tokens[1]) = (_fromToken, _toToken);
        (uint256[] memory prices, bool[] memory successes) = oracle.getFreshPrice(tokens);
        for (uint i; i < successes.length;) {
            if (!successes[i]) revert PriceFailed(tokens[i]);
            unchecked { i++; }
        }

        minAmountOut = (prices[0] * _amount * 10 ** IERC20MetadataUpgradeable(_toToken).decimals() * slippage) / 
            (prices[1] * 10 ** IERC20MetadataUpgradeable(_fromToken).decimals() * 1 ether);
    }

    /// @dev _fromToken is pulled into this contract from the caller, swap is executed according to
    /// the stored data, resulting _toTokens are sent to the caller
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amount Amount of _fromToken to use in the swap
    /// @param _minAmountOut Minimum amount of _toToken that is acceptable to be returned to caller
    /// @return outputAmount Amount of _toToken returned to the caller
    function _swap(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        uint256 _minAmountOut
    ) private returns (uint256 outputAmount) {
        IERC20MetadataUpgradeable(_fromToken).safeTransferFrom(msg.sender, address(this), _amount);
        _executeSwap(_fromToken, _toToken, _amount, _minAmountOut);
        outputAmount = IERC20MetadataUpgradeable(_toToken).balanceOf(address(this));
        IERC20MetadataUpgradeable(_toToken).safeTransfer(msg.sender, outputAmount);
    }

    /// @dev Fetch the stored swap info for the route between the two tokens, insert the encoded
    /// balance and minimum output to the payload and call the stored router with the data
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amount Amount of _fromToken to use in the swap
    /// @param _minAmountOut Minimum amount of _toToken that is acceptable to be returned to caller
    function _executeSwap(
        address _fromToken,
        address _toToken,
        uint256 _amount,
        uint256 _minAmountOut
    ) private {
        SwapInfo memory swapData = swapInfo[_fromToken][_toToken];
        address router = swapData.router;
        bytes memory data = swapData.data;

        data = _insertData(data, swapData.amountIndex, abi.encode(_amount));

        bytes memory minAmountData = swapData.minAmountSign >= 0
            ? abi.encode(_minAmountOut)
            : abi.encode(-int256(_minAmountOut));
            
        data = _insertData(data, swapData.minIndex, minAmountData);

        IERC20MetadataUpgradeable(_fromToken).forceApprove(router, type(uint256).max);
        (bool success,) = router.call(data);
        if (!success) revert SwapFailed(router, data);
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
            _data.slice(_index + 32, data.length - (_index + 32))
        );
    }

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

    /// @notice Owner function to set the oracle used to calculate the minimum outputs
    /// @dev No validation checks
    /// @param _oracle Address of the new oracle
    function setOracle(address _oracle) external onlyOwner {
        oracle = IBeefyOracle(_oracle);
        emit SetOracle(_oracle);
    }
}
