// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import { UniswapV3OracleLibrary, IUniswapV3Pool } from "../../utils/UniswapV3OracleLibrary.sol";
import { BeefyOracleHelper, IBeefyOracle, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle for UniswapV3
/// @author Beefy, @kexley
/// @notice On-chain oracle using UniswapV3
contract BeefyOracleUniswapV3 {

    /// @notice Fetch price from the UniswapV3 pools using the TWAP observations
    /// @param _data Payload from the central oracle with the addresses of the token route, pool 
    /// route and TWAP periods in seconds
    /// @return price Retrieved price from the chained quotes
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external returns (uint256 price, bool success) {
        (address[] memory tokens, address[] memory pools, uint256[] memory twapPeriods) = 
            abi.decode(_data, (address[], address[], uint256[]));

        int24[] memory ticks = new int24[](pools.length);
        for (uint i; i < pools.length; i++) {
            (ticks[i],) = UniswapV3OracleLibrary.consult(pools[i], uint32(twapPeriods[i]));
        }

        int256 chainedTick = UniswapV3OracleLibrary.getChainedPrice(tokens, ticks);

        // Do not let the conversion overflow
        if (chainedTick > type(int24).max) return (0, false);

        uint256 amountOut = UniswapV3OracleLibrary.getQuoteAtTick(
            int24(chainedTick),
            10 ** IERC20MetadataUpgradeable(tokens[0]).decimals()
        );

        price = BeefyOracleHelper.priceFromBaseToken(
            msg.sender, tokens[tokens.length - 1], tokens[0], amountOut
        );
        if (price != 0) success = true;
    }

    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded addresses of the token route, pool route and TWAP periods
    function validateData(bytes calldata _data) external view {
        (address[] memory tokens, address[] memory pools, uint256[] memory twapPeriods) = 
            abi.decode(_data, (address[], address[], uint256[]));

        if (tokens.length != pools.length + 1 || tokens.length != twapPeriods.length + 1) {
            revert BeefyOracleErrors.ArrayLength();
        }
        
        uint256 basePrice = IBeefyOracle(msg.sender).getPrice(tokens[0]);
        if (basePrice == 0) revert BeefyOracleErrors.NoBasePrice(tokens[0]);

        uint256 poolLength = pools.length;
        for (uint i; i < poolLength;) {
            address fromToken = tokens[i];
            address toToken = tokens[i + 1];
            address pool = pools[i];
            address token0 = IUniswapV3Pool(pool).token0();
            address token1 = IUniswapV3Pool(pool).token1();

            if (fromToken != token0 && fromToken != token1) {
                revert BeefyOracleErrors.TokenNotInPair(fromToken, pool);
            }
            if (toToken != token0 && toToken != token1) {
                revert BeefyOracleErrors.TokenNotInPair(toToken, pool);
            }
            unchecked { ++i; }
        }
    }
}
