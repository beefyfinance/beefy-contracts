// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import {DSTest} from "../forgeLib/test.sol";

// Contracts
import {BeefyVaultV6} from "../../contracts/BIFI/vaults/BeefyVaultV6.sol";
import {StrategyCommonChefLP} from "../../contracts/BIFI/strategies/Common/StrategyCommonChefLP.sol";

// Interfaces
import {IBeefyVaultV6} from "../../contracts/BIFI/interfaces/beefy/IBeefyVaultV6.sol";
import {IStrategyComplete} from "../../contracts/BIFI/interfaces/beefy/IStrategyComplete.sol";

contract ProdVaultTest is DSTest {

    // Input your vault to test here.
    IBeefyVaultV6 vault = IBeefyVaultV6(0x1313b9C550bbDF55Fc06f63a41D8BDC719d056A6);
    IStrategyComplete strategy;
    
    function setup() external {
        strategy = IStrategyComplete(vault.strategy());


    }
}