// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { IChainlinkMorpho } from "../../interfaces/oracle/IChainlinkMorpho.sol";
import { IERC4626 } from "../../interfaces/common/IERC4626.sol";
import { BeefyOracleHelper, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle for Morpho Chainlink oracles
/// @author Beefy, @jackgale.eth
/// @notice Onchain oracle using Morpho Chainlink oracles for pricing
library BeefyOracleMorphoChainlink {

    // @notice Fetch price from the Morpho Chainlink feed for a BASE_VAULT (an ERC4626 asset that is the deposit asset for the Morpho V2 Vault) and scale to 18 decimals
    // @params _data Payload from the central oracle with the address of the Morpho Chainlink feedeth
    // @return price Retrieved price from the Morpho Chainlink feed
    // @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external view returns (uint256 price, bool success) {
        address chainlink = abi.decode(_data, (address));
        address vault = IChainlinkMorpho(chainlink).BASE_VAULT();
        try IERC4626(vault).decimals() returns (uint8 decimals) {
            try IChainlinkMorpho(chainlink).price() returns (uint256 prices) {
                price = BeefyOracleHelper.scaleAmount(uint256(prices), decimals);
                success = true;
            } catch {}
        } catch {}
    }

    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded Morpho Chainlink feed address
    function validateData(bytes calldata _data) external view {
        address chainlink = abi.decode(_data, (address));
        address vault = IChainlinkMorpho(chainlink).BASE_VAULT();
        try IERC4626(vault).decimals() returns (uint8) {
            try IChainlinkMorpho(chainlink).price() {
            } catch { revert BeefyOracleErrors.NoAnswer(); }
        } catch { revert BeefyOracleErrors.NoAnswer(); }
    }
}