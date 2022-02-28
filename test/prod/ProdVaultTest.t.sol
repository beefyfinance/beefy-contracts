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

    IBeefyVaultV6 vault;
    IStrategyComplete strategy;
    
    function setup() external {

    }
}