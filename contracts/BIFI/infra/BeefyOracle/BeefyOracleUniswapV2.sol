// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import { IUniswapV2Pair } from "../../interfaces/common/IUniswapV2Pair.sol";
import { BeefyOracleHelper, IBeefyOracle, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle for UniswapV2
/// @author Beefy, @kexley
/// @notice On-chain oracle using UniswapV2
/// @dev Observations are stored here as UniswapV2 pairs do not store historical observations
contract BeefyOracleUniswapV2 {

    /// @dev Struct of stored price averages and the most recent observation of a pair
    /// @param priceAverage0 Average price of token0
    /// @param priceAverage1 Average price of token1
    /// @param observation Cumulative prices of token0 and token1
    struct Price {
        uint256 priceAverage0;
        uint256 priceAverage1;
        Observation observation;
    }

    /// @dev Struct of the stored latest observation of a pair
    /// @param price0 Cumulative price of token0
    /// @param price1 Cumulative price of token1
    /// @param timestamp Timestamp of the observation
    struct Observation {
        uint256 price0;
        uint256 price1;
        uint256 timestamp;
    }

    /// @notice Stored last average prices of tokens in a pair
    mapping(address => Price) public prices;

    /// @notice Pair has been updated with average prices
    /// @param pair Pair address
    /// @param priceAverage0 Average price of token0
    /// @param priceAverage1 Average price of token1
    event PairUpdated(address indexed pair, uint256 priceAverage0, uint256 priceAverage1);

    /// @notice Fetch price from the UniswapV2 pairs using the TWAP observations
    /// @param _data Payload from the central oracle with the addresses of the token route, pairs 
    /// route and TWAP periods in seconds
    /// @return price Retrieved price from the chained quotes
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external returns (uint256 price, bool success) {
        (address[] memory tokens, address[] memory pairs, uint256[] memory twapPeriods) = 
            abi.decode(_data, (address[], address[], uint256[]));

        uint256 amount = 10 ** IERC20MetadataUpgradeable(tokens[0]).decimals();
        uint256 pairLength = pairs.length;
        for (uint i; i < pairLength;) {
            address pair = pairs[i];
            _updatePair(pair, twapPeriods[i]);
            amount = _getAmountOut(pair, tokens[i], amount);
            unchecked { ++i; }
        }

        price = BeefyOracleHelper.priceFromBaseToken(
            msg.sender, tokens[tokens.length - 1], tokens[0], amount
        );
        if (price != 0) success = true;
    }

    /// @dev Update the stored price averages and observation for a UniswapV2 pair if outside the TWAP
    /// period or tracking a new pair. Initial average prices should not be trusted
    /// @param _pair UniswapV2 pair to update
    /// @param _twapPeriod TWAP period minimum in seconds
    function _updatePair(address _pair, uint256 _twapPeriod) private {
        Observation memory observation = prices[_pair].observation;
        uint256 timeElapsed = block.timestamp - observation.timestamp;

        if (timeElapsed > _twapPeriod) {
            (uint112 reserve0, uint112 reserve1, uint256 lastUpdate) = IUniswapV2Pair(_pair).getReserves();
            uint256 price0 = IUniswapV2Pair(_pair).price0CumulativeLast();
            uint256 price1 = IUniswapV2Pair(_pair).price1CumulativeLast();

            if (block.timestamp > lastUpdate) {
                uint256 unsyncTime = block.timestamp - lastUpdate;
                price0 += (2**112 * uint256(reserve1) / reserve0) * unsyncTime;
                price1 += (2**112 * uint256(reserve0) / reserve1) * unsyncTime;
            }

            uint256 priceAverage0;
            uint256 priceAverage1;
            if (prices[_pair].observation.timestamp > 0) {
                priceAverage0 = (price0 - observation.price0) * 1 ether / (timeElapsed * 2**112);
                priceAverage1 = (price1 - observation.price1) * 1 ether / (timeElapsed * 2**112);
            } else {
                priceAverage0 = uint256(reserve1) * 1 ether / reserve0;
                priceAverage1 = uint256(reserve0) * 1 ether / reserve1;
            }

            prices[_pair] = Price(priceAverage0, priceAverage1, Observation(price0, price1, block.timestamp));
            emit PairUpdated(_pair, priceAverage0, priceAverage1);
        }
    }

    /// @dev Use the stored price average to get the amount out
    /// @param _pair UniswapV2 pair
    /// @param _tokenIn Address of the token being swapped into the pair
    /// @param _amountIn Amount of the token being swapped in
    /// @return amountOut Amount of the output token being received from the swap
    function _getAmountOut(
        address _pair,
        address _tokenIn,
        uint256 _amountIn
    ) private view returns (uint256 amountOut) {
        uint256 priceAverage = IUniswapV2Pair(_pair).token0() == _tokenIn 
            ? prices[_pair].priceAverage0
            : prices[_pair].priceAverage1;
        amountOut = priceAverage * _amountIn / 1 ether;
    }

    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded addresses of the token route, pair route and TWAP periods
    function validateData(bytes calldata _data) external view {
        (address[] memory tokens, address[] memory pairs, uint256[] memory twapPeriods) = 
            abi.decode(_data, (address[], address[], uint256[]));

        if (tokens.length != pairs.length + 1 || tokens.length != twapPeriods.length + 1) {
            revert BeefyOracleErrors.ArrayLength();
        }

        uint256 basePrice = IBeefyOracle(msg.sender).getPrice(tokens[0]);
        if (basePrice == 0) revert BeefyOracleErrors.NoBasePrice(tokens[0]);

        uint256 pairLength = pairs.length;
        for (uint i; i < pairLength;) {
            address fromToken = tokens[i];
            address toToken = tokens[i + 1];
            address pair = pairs[i];
            address token0 = IUniswapV2Pair(pair).token0();
            address token1 = IUniswapV2Pair(pair).token1();
            
            if (fromToken != token0 && fromToken != token1) {
                revert BeefyOracleErrors.TokenNotInPair(fromToken, pair);
            }
            if (toToken != token0 && toToken != token1) {
                revert BeefyOracleErrors.TokenNotInPair(toToken, pair);
            }
            unchecked { ++i; }
        }
    }
}
