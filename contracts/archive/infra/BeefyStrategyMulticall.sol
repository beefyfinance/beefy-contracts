// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/beefy/IVault.sol";

contract BeefyStrategyMulticall {

    function getStrategy(address[] calldata vaults) external view returns (address[] memory) {
        address[] memory strategies = new address[](vaults.length);

        for (uint i = 0; i < vaults.length; i++) {
            strategies[i] = address(IVault(vaults[i]).strategy());
        }

        return strategies;
    }
}