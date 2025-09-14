// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IStrategyMorphoMerklFeeOnLend {
    struct StrategyMorphoMerklFeeOnLendStorage {
        address morphoVault;
        address claimer;
    }
}