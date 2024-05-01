// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IChainlink } from "../../interfaces/oracle/IChainlink.sol";
import { BeefyOracleHelper, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle using Chainlink
/// @author Beefy, @kexley
/// @notice On-chain oracle using Chainlink
library BeefyOracleChainlink {

    /// @notice Fetch price from the Chainlink feed and scale to 18 decimals
    /// @param _data Payload from the central oracle with the address of the Chainlink feed
    /// @return price Retrieved price from the Chainlink feed
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external view returns (uint256 price, bool success) {
        address chainlink = abi.decode(_data, (address));
        try IChainlink(chainlink).decimals() returns (uint8 decimals) {
            try IChainlink(chainlink).latestAnswer() returns (int256 latestAnswer) {
                price = BeefyOracleHelper.scaleAmount(uint256(latestAnswer), decimals);
                success = true;
            } catch {}
        } catch {}
    }

    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded Chainlink feed address
    function validateData(bytes calldata _data) external view {
        address chainlink = abi.decode(_data, (address));
        try IChainlink(chainlink).decimals() returns (uint8) {
            try IChainlink(chainlink).latestAnswer() returns (int256) {
            } catch { revert BeefyOracleErrors.NoAnswer(); }
        } catch { revert BeefyOracleErrors.NoAnswer(); }
    }
}
