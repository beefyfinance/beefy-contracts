// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import { IBeefyOracle } from "../../interfaces/oracle/IBeefyOracle.sol";
import { BeefyOracleErrors } from "./BeefyOracleErrors.sol";

/// @title Beefy Oracle Helper
/// @author Beefy, @kexley
/// @notice Helper functions for Beefy oracles
library BeefyOracleHelper {

    /// @dev Calculate the price of the output token in 18 decimals given the base token price 
    /// and the amount out received from swapping 1 unit of the base token
    /// @param _oracle Central Beefy oracle which stores the base token price
    /// @param _token Address of token to calculate the price of
    /// @param _baseToken Address of the base token used in the price chain
    /// @param _amountOut Amount received from swapping 1 unit of base token into the target token
    /// @return price Price of the target token in 18 decimals
    function priceFromBaseToken(
        address _oracle,
        address _token,
        address _baseToken,
        uint256 _amountOut
    ) internal returns (uint256 price) {
        (uint256 basePrice,) = IBeefyOracle(_oracle).getFreshPrice(_baseToken);
        uint8 decimals = IERC20MetadataUpgradeable(_token).decimals();
        _amountOut = scaleAmount(_amountOut, decimals);
        price =  basePrice * 1 ether / _amountOut;
    }

    /// @dev Scale an input amount to 18 decimals
    /// @param _amount Amount to be scaled up or down
    /// @param _decimals Decimals that the amount is already in
    /// @return scaledAmount New scaled amount in 18 decimals
    function scaleAmount(
        uint256 _amount,
        uint8 _decimals
    ) internal pure returns (uint256 scaledAmount) {
        scaledAmount = _decimals == 18 ? _amount : _amount * 10 ** 18 / 10 ** _decimals;
    }
}
