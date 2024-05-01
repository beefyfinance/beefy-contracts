// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import { ISolidlyPair} from "../../interfaces/common/ISolidlyPair.sol";
import { BeefyOracleHelper, IBeefyOracle, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle for Solidly
/// @author Beefy, @kexley
/// @notice On-chain oracle using Solidly
contract BeefyOracleSolidly {

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
            revert BeefyOracleErrors.ArrayLength();
        }
        
        uint256 basePrice = IBeefyOracle(msg.sender).getPrice(tokens[0]);
        if (basePrice == 0) revert BeefyOracleErrors.NoBasePrice(tokens[0]);

        uint256 poolLength = pools.length;
        for (uint i; i < poolLength;) {
            address fromToken = tokens[i];
            address toToken = tokens[i + 1];
            address pool = pools[i];
            address token0 = ISolidlyPair(pool).token0();
            address token1 = ISolidlyPair(pool).token1();

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
