// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BeefyVaultV7.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

// Beefy Finance Vault V7 Proxy Factory
// Minimal proxy pattern for creating new Beefy vaults
contract BeefyVaultV7Factory {
  using ClonesUpgradeable for address;

  // Contract template for deploying proxied Beefy vaults
  BeefyVaultV7 public instance;

  event ProxyCreated(address proxy);

  // Initializes the Factory with an instance of the Beefy Vault V7
  constructor(address _instance) {
    if (_instance == address(0)) {
      instance = new BeefyVaultV7();
    } else {
      instance = BeefyVaultV7(_instance);
    }
  }

  // Creates a new Beefy Vault V7 as a proxy of the template instance
  // A reference to the new proxied Beefy Vault V7
  function cloneVault() external returns (BeefyVaultV7) {
    return BeefyVaultV7(cloneContract(address(instance)));
  }

  // Deploys and returns the address of a clone that mimics the behaviour of `implementation`
  function cloneContract(address implementation) public returns (address) {
    address proxy = implementation.clone();
    emit ProxyCreated(proxy);
    return proxy;
  }
}