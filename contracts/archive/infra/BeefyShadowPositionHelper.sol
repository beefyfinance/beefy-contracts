// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/LiquidityAmounts.sol";
import "../utils/TickMath.sol";

interface INftPositionManager {
    function positions(uint256 nftId)
        external
        view
        returns (address, address, int24, int24, int24, uint128, uint256, uint256, uint128, uint128);
}

interface ILpToken {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

contract BeefyShadowPositionHelper {
    using TickMath for int24;

    function getPositionTokens(
        uint256 posId,
        address lpToken,
        address nftManager
    ) external view returns (uint256, uint256, uint128) {
        (,,,int24 lowerTick, int24 upperTick, uint128 liquidity,,,,) 
            = INftPositionManager(nftManager).positions(posId);
        (, int24 currentTick,,,,,) = ILpToken(lpToken).slot0();

        return _getAmountForLiquidity(currentTick, lowerTick, upperTick, liquidity);
    }

    function _getAmountForLiquidity(
        int24 currentTick,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) private pure returns (uint256, uint256,uint128){
        (uint256 amountToken0, uint256 amountToken1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(currentTick),
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            liquidity
        );

        return(amountToken0, amountToken1, liquidity);
    }

}