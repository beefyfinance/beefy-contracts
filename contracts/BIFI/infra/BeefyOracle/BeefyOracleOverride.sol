// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { BeefyOracleHelper, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle Override
/// @author Beefy
/// @notice On-chain oracle override for use with hard to get on chain price feeds
library BeefyOracleOverride {

    /// @notice Return 0
    /// @return price Retrieved price from the Chainlink feed
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata) external pure returns (uint256 price, bool success) {
        return (BeefyOracleHelper.scaleAmount(uint256(1000000000000000000000000), uint8(8)), true);
    }

    /// @notice Data validation 
    function validateData(bytes calldata) external view {}
}
