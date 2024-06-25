// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IChainlink } from "../../interfaces/oracle/IChainlink.sol";
import { BeefyOracleHelper, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle using Chainlink with an ETH base
/// @author Beefy, @kexley
/// @notice On-chain oracle using Chainlink with an ETH base
library BeefyOracleChainlinkEthBase {

    /// @notice Fetch price from the Chainlink feed and scale to 18 decimals
    /// @param _data Payload from the central oracle with the address of the Chainlink feed
    /// @return price Retrieved price from the Chainlink feed
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external view returns (uint256 price, bool success) {
        (address chainlink, address chainlinkEth) = abi.decode(_data, (address, address));
        uint256 ethPrice;

        // Get ETH price
        try IChainlink(chainlinkEth).decimals() returns (uint8 decimals) {
            try IChainlink(chainlinkEth).latestAnswer() returns (int256 latestAnswer) {
                ethPrice = BeefyOracleHelper.scaleAmount(uint256(latestAnswer), decimals);
            } catch {}
        } catch {}

        // Get token price
        try IChainlink(chainlink).decimals() returns (uint8 decimals) {
            try IChainlink(chainlink).latestAnswer() returns (int256 latestAnswer) {
                price = BeefyOracleHelper.scaleAmount(uint256(latestAnswer), decimals) * ethPrice / 1e18;
                success = true;
            } catch {}
        } catch {}
    }

    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded Chainlink feed address
    function validateData(bytes calldata _data) external view {
        (address chainlink, address chainlinkEth) = abi.decode(_data, (address, address));

        try IChainlink(chainlinkEth).decimals() returns (uint8) {
            try IChainlink(chainlinkEth).latestAnswer() returns (int256) {
            } catch { revert BeefyOracleErrors.NoAnswer(); }
        } catch { revert BeefyOracleErrors.NoAnswer(); }

        try IChainlink(chainlink).decimals() returns (uint8) {
            try IChainlink(chainlink).latestAnswer() returns (int256) {
            } catch { revert BeefyOracleErrors.NoAnswer(); }
        } catch { revert BeefyOracleErrors.NoAnswer(); }
    }
}
