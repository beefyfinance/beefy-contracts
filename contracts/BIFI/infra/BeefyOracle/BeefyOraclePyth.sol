// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IPyth } from "../../interfaces/oracle/IPyth.sol";
import { BeefyOracleHelper, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle using Pyth
/// @author Beefy, @kexley
/// @notice On-chain oracle using Pyth
library BeefyOraclePyth {

    /// @notice Fetch price from the Pyth feed and scale to 18 decimals
    /// @param _data Payload from the central oracle with the address and id of the Pyth feed
    /// @return price Retrieved price from the Pyth feed
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external view returns (uint256 price, bool success) {
        (address pyth, bytes32 priceId) = abi.decode(_data, (address, bytes32));
        try IPyth(pyth).getPrice(priceId) returns (IPyth.Price memory answer) {
            price = BeefyOracleHelper.scaleAmount(uint256(int256(answer.price)), uint8(int8(answer.expo)));
            success = true;
        } catch {}
    }

    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded Pyth feed address
    function validateData(bytes calldata _data) external view {
        (address pyth, bytes32 priceId) = abi.decode(_data, (address, bytes32));
        try IPyth(pyth).getPrice(priceId) returns (IPyth.Price memory) {
        } catch { revert BeefyOracleErrors.NoAnswer(); }
    }
}
