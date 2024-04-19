// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IBeefySwapper } from "../../interfaces/beefy/IBeefySwapper.sol";
import { IBeefyOracle } from "../../interfaces/oracle/IBeefyOracle.sol";
import { IBeefyZapRouter } from "../../interfaces/beefy/IBeefyZapRouter.sol";

/// @title Swapper functions inherited by strategies
/// @author Beefy, @kexley
/// @notice Swapper logic
contract StrategySwapper is OwnableUpgradeable {
    /// @notice Swapper used to swap tokens
    IBeefySwapper public beefySwapper;

    /// @notice Oracle used to price tokens
    IBeefyOracle public beefyOracle;

    /// @notice New Beefy Swapper is set
    /// @param beefySwapper New Beefy Swapper address
    /// @param beefyOracle New Beefy Oracle address
    event SetBeefySwapper(address beefySwapper, address beefyOracle);

    /// @dev Initialization function to set the swapper and oracle addresses
    /// @param _beefySwapper Swapper used to swap tokens
    function __StrategySwapper_init(address _beefySwapper) internal onlyInitializing {
        beefySwapper = IBeefySwapper(_beefySwapper);
        beefyOracle = IBeefyOracle(beefySwapper.oracle());
        emit SetBeefySwapper(_beefySwapper, address(beefyOracle));
    }

    /// @dev Simple swap function to be inherited
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of the token to swap from
    /// @return amountOut Amount returned by the swap
    function _swap(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) internal returns (uint256 amountOut) {
        return beefySwapper.swap(_fromToken, _toToken, _amountIn);
    }

    /// @dev Simple swap function to be inherited
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @return amountOut Amount returned by the swap
    function _swap(
        address _fromToken,
        address _toToken
    ) internal returns (uint256 amountOut) {
        return beefySwapper.swap(_fromToken, _toToken, IERC20Upgradeable(_fromToken).balanceOf(address(this)));
    }

    /// @dev Simple quote function to be inherited
    /// @param _fromToken Token to swap from
    /// @param _toToken Token to swap to
    /// @param _amountIn Amount of the token to swap from
    /// @return estimatedAmountOut Estimated amount returned by the swap
    function _getAmountOut(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) internal view returns (uint256 estimatedAmountOut) {
        return beefySwapper.getAmountOut(_fromToken, _toToken, _amountIn);
    }

    /// @notice Set the stored swap steps for the route between many tokens
    /// @param _fromTokens Tokens to swap from
    /// @param _toTokens Tokens to swap to
    /// @param _swapSteps Swap steps to store
    function setSwapSteps(
        address[] calldata _fromTokens,
        address[] calldata _toTokens,
        IBeefyZapRouter.Step[][] calldata _swapSteps
    ) external onlyOwner {
        beefySwapper.setSwapSteps(_fromTokens, _toTokens, _swapSteps);
    }

    /// @notice Set a sub oracle and data for multiple tokens
    /// @param _tokens Address of the tokens being fetched
    /// @param _oracles Address of the libraries used to calculate the price
    /// @param _datas Payload specific to the tokens that will be used by the library
    function setOracles(
        address[] calldata _tokens,
        address[] calldata _oracles,
        bytes[] calldata _datas
    ) external onlyOwner {
        beefyOracle.setOracles(_tokens, _oracles, _datas);
    }

    /// @notice Set a new Beefy Swapper
    /// @param _beefySwapper New Beefy Swapper
    function setBeefySwapper(address _beefySwapper) external onlyOwner {
        beefySwapper = IBeefySwapper(_beefySwapper);
        beefyOracle = IBeefyOracle(beefySwapper.oracle());
        emit SetBeefySwapper(_beefySwapper, address(beefyOracle));
    }

    uint256[49] private __gap;
}
