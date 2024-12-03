// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBeefySwapper {
    /// @notice Swap between two tokens with slippage calculated using the oracle
    /// @dev Caller must have already approved this contract to spend the _fromToken.
    /// After the swap the _toToken token is sent directly to the caller
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @return amountOut Amount of _toToken returned to the caller
    function swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) external returns (uint256 amountOut);

    /// @notice Swap between two tokens with slippage provided by the caller
    /// @dev Caller must have already approved this contract to spend the _fromToken.
    /// After the swap the _toToken token is sent directly to the caller
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
    ) external returns (uint256 amountOut);

    /// @notice Swap between tokens along a route with slippage calculated using the oracle
    /// @dev Caller must have already approved this contract to spend the _route[0].
    /// After the swap the _route[_route.length-1] token is sent directly to the caller
    /// @param _route List of tokens to swap via
    /// @param _amountIn Amount of _route[0] to use in the swap
    /// @return amountOut Amount of _route[_route.length-1] returned to the calle
    function swap(
        address[] calldata _route,
        uint256 _amountIn
    ) external returns (uint256 amountOut);

    /// @notice Swap between tokens along a route with slippage provided by the caller
    /// @dev Caller must have already approved this contract to spend the _route[0]. After the
    /// swap the _route[_route.length-1] token is sent directly to the caller
    /// @param _route List of tokens to swap via
    /// @param _amountIn Amount of _route[0] to use in the swap
    /// @param _minAmountOut Minimum amount of _route[_route.length-1] that is acceptable to be returned to caller
    /// @return amountOut Amount of _route[_route.length-1] returned to the caller
    function swap(
        address[] calldata _route,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external returns (uint256 amountOut);

    /// @notice Get the amount out from a simulated swap with slippage and non-fresh prices
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of _fromToken to use in the swap
    /// @return amountOut Amount of _toTokens returned from the swap
    function getAmountOut(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) external view returns (uint256 amountOut);

    /// @notice Get whether a swap can be attempted between two tokens
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @return If there is a direct swap, or a multi-hop route between the two tokens
    function hasSwap(
        address _fromToken,
        address _toToken
    ) external view returns (bool);

    /// @notice Stored swap info for a token
    function swapInfo(
        address _fromToken,
        address _toToken
    ) external view returns (
        address router,
        bytes memory data,
        uint256 amountIndex,
        uint256 minIndex,
        int8 minAmountSign
    );

    /// @notice Stored multi-hop routes for swapping between two tokens
    function swapRoute(
        address _fromToken,
        address _toToken,
        uint256 _index
    ) external view returns (address);

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
}

interface ISimplifiedSwapInfo {
    function swapInfo(address _fromToken, address _toToken) external view returns (address router, bytes calldata data);
}