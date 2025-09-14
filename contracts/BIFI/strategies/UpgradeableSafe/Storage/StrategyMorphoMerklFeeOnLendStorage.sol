// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { IStrategyMorphoMerklFeeOnLend } from "../Interfaces/IStrategyMorphoMerklFeeOnLend.sol";

/// @title Base All To Native Factory Strat Storage Utils
/// @author Beefy
/// @notice Storage utilities for base all to native factory strat
abstract contract StrategyMorphoMerklFeeOnLendStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("beefy.storage.StrategyMorphoMerklFeeOnLend")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StrategyMorphoMerklFeeOnLendStorageLocation =
        0x88c032b10d4ebec85eab0c277c6574cd969937e5c2fc658c01da3853dc183d00;

    /// @dev Get base all to native factory strat storage
    /// @return $ Storage pointer
    function getStrategyMorphoMerklFeeOnLendStorage()
        internal
        pure
        returns (IStrategyMorphoMerklFeeOnLend.StrategyMorphoMerklFeeOnLendStorage storage $)
    {
        assembly {
            $.slot := StrategyMorphoMerklFeeOnLendStorageLocation
        }
    }
}