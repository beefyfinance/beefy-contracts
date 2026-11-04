// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {StrategyAero} from "./StrategyAero.sol";
import {IArbSys} from "../../interfaces/arbitrum/IArbSys.sol";

/// @title Beefy Autocompounding Vault. Version: Aero
/// @author jackgale.eth, Beefy
/// @notice With overridden method for reading block number to match Aero gauge.
contract StrategyPassiveManagerAeroArb is StrategyAero {
    function _blockNumber() internal view override returns (uint256) {
        return IArbSys(address(0x64)).arbBlockNumber();
    }
}