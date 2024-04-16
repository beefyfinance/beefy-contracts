// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IBeefyZapRouter } from "./IBeefyZapRouter.sol";

interface IBeefySwapper {
    function swap(
        address fromToken,
        address toToken,
        uint256 amountIn
    ) external returns (uint256 amountOut);

    function swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    function getAmountOut(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) external view returns (uint256 amountOut);

    function setSwapSteps(
        address _fromToken,
        address _toToken,
        IBeefyZapRouter.Step[] calldata _swapSteps
    ) external;

    function setManySwapSteps(
        address[] calldata _fromTokens,
        address[] calldata _toTokens,
        IBeefyZapRouter.Step[][] calldata _swapSteps
    ) external;

    function oracle() external view returns (address);
}
