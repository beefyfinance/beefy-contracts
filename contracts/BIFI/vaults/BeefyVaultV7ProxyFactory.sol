// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.7.0;

import "./BeefyVaultV7.sol";
import "../utils/ProxyFactory.sol";

// Beefy Finance Vault V7 Proxy Factory
// Minimal proxy pattern for creating new Beefy vaults
contract BeefyVaultV7ProxyFactory is ProxyFactory {

  // Contract template for deploying proxied Prize Pools
  BeefyVaultV7 public instance;

  // Initializes the Factory with an instance of the Beefy Vault V7
  constructor () public {
    instance = new BeefyVaultV7();
  }

  // Creates a new Beefy Vault V7 as a proxy of the template instance
  // A reference to the new proxied Beefy Vault V7
  function create() external returns (BeefyVaultV7) {
    return BeefyVaultV7(deployMinimal(address(instance), ""));
  }
}