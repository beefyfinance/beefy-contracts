// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { BeefyOracleHelper } from "./BeefyOracleHelper.sol";
import { ISolidlyPair} from "../../interfaces/common/ISolidlyPair.sol";

/// @title Beefy Oracle for Solidly
/// @author Beefy, @kexley
/// @notice On-chain oracle using Solidly
library BeefyOracleSolidly {

    /// @dev Array length is not correct
    error ArrayLength();

    /// @dev No price for base token
    /// @param token Base token
    error NoBasePrice(address token);

    /// @dev Token is not present in the pair
    /// @param token Input token
    /// @param pair Solidly pair
    error TokenNotInPair(address token, address pair);

    /// @notice Fetch price from the Solidly pairs using the TWAP observations
    /// @param _data Payload from the central oracle with the addresses of the token route, pool 
    /// route and TWAP periods counted in 30 minute increments
    /// @return price Retrieved price from the chained quotes
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external returns (uint256 price, bool success) {
        (address[] memory tokens, address[] memory pools, uint256[] memory twapPeriods) = 
            abi.decode(_data, (address[], address[], uint256[]));

        uint256 amount = 10 ** IERC20MetadataUpgradeable(tokens[0]).decimals();
        for (uint i; i < pools.length; i++) {
            amount = ISolidlyPair(pools[i]).quote(tokens[i], amount, twapPeriods[i]);
        }

        price = BeefyOracleHelper.priceFromBaseToken(
            msg.sender, tokens[tokens.length - 1], tokens[0], amount
        );
        if (price != 0) success = true;
    }

    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded addresses of the token route, pool route and TWAP periods
    function validateData(bytes calldata _data) external view {
        (address[] memory tokens, address[] memory pools, uint256[] memory twapPeriods) = 
            abi.decode(_data, (address[], address[], uint256[]));

        if (tokens.length != pools.length + 1 || tokens.length != twapPeriods.length + 1) {
            revert ArrayLength();
        }
        
        uint256 basePrice = IBeefyOracle(msg.sender).getPrice(tokens[0]);
        if (basePrice == 0) revert NoBasePrice(tokens[0]);

        for (uint i; i < pools.length; i++) {
            address token = tokens[i];
            address pool = pools[i];
            if (token != ISolidlyPair(pool).token0() || token != ISolidlyPair(pool).token1()) {
                revert TokenNotInPair(token, pool);
            }
        }
    }
}
