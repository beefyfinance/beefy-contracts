// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IChainlink } from "../../interfaces/oracle/IChainlink.sol";
import { IStableRouter } from "../../interfaces/common/IStableRouter.sol";
import { BeefyOracleHelper, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle using Stable Router
/// @author Beefy, @kexley
/// @notice On-chain oracle using Stable Router
library BeefyOracleStableRouter {

    /// @notice Fetch price from the Chainlink feed and scale to 18 decimals
    /// @param _data Payload from the central oracle with the address of the Chainlink feed
    /// @return price Retrieved price from the Chainlink feed
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external view returns (uint256 price, bool success) {
        (address chainlink, address stableRouter) = abi.decode(_data, (address, address));
        uint256 underlyingPrice;

        // Get ETH price
        try IChainlink(chainlink).decimals() returns (uint8 decimals) {
            try IChainlink(chainlink).latestAnswer() returns (int256 latestAnswer) {
                underlyingPrice = BeefyOracleHelper.scaleAmount(uint256(latestAnswer), decimals);
            } catch {}
        } catch {}

        // Get token price
        price = underlyingPrice * IStableRouter(stableRouter).getVirtualPrice() / 1e18;
        if (price != 0) success = true;
    }

    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded Chainlink feed address and Stable Router address
    function validateData(bytes calldata _data) external view {
        (address chainlink, address stableRouter) = abi.decode(_data, (address, address));

        try IChainlink(chainlink).decimals() returns (uint8) {
            try IChainlink(chainlink).latestAnswer() returns (int256) {
            } catch { revert BeefyOracleErrors.NoAnswer(); }
        } catch { revert BeefyOracleErrors.NoAnswer(); }

        try IStableRouter(stableRouter).getVirtualPrice() returns (uint256) {
        } catch { revert BeefyOracleErrors.NoAnswer(); }
    }
}
