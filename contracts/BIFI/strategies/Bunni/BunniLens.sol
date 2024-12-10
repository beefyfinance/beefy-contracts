// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/TickMath.sol";
import "../../utils/LiquidityAmounts.sol";
import "./IBunni.sol";

contract BunniLens {

    function tokenBalances(address bunniToken) external view returns (uint256 amount0, uint256 amount1, uint256 totalSupply) {
        address hub = IBunniToken(bunniToken).hub();
        address pool = IBunniToken(bunniToken).pool();
        int24 tickLower = IBunniToken(bunniToken).tickLower();
        int24 tickUpper = IBunniToken(bunniToken).tickUpper();
        (uint128 liquidity,,,,) = IUniV3Pool(pool).positions(keccak256(abi.encodePacked(hub, tickLower, tickUpper)));
        (uint160 sqrtPriceX96,,,,,,) = IUniV3Pool(pool).slot0();

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );

        totalSupply = IBunniToken(bunniToken).totalSupply();
    }
}