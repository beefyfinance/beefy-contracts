// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BeefyVaultV8.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

// Beefy Finance Vault V8 Proxy Factory
// Minimal proxy pattern for creating new Beefy vaults
contract BeefyVaultV8Factory {
  using ClonesUpgradeable for address;

  // Contract template for deploying proxied Beefy vaults
  BeefyVaultV8 public instance;

  event ProxyCreated(address proxy);

  // Initializes the Factory with an instance of the Beefy Vault V8
  constructor(address _instance) {
    if (_instance == address(0)) {
      instance = new BeefyVaultV8();
    } else {
      instance = BeefyVaultV8(_instance);
    }
  }

  // Creates a new Beefy Vault V8 as a proxy of the template instance
  // A reference to the new proxied Beefy Vault V8
  function cloneVault() external returns (BeefyVaultV8) {
    return BeefyVaultV8(cloneContract(address(instance)));
  }

  // Deploys and returns the address of a clone that mimics the behaviour of `implementation`
  function cloneContract(address implementation) public returns (address) {
    address proxy = implementation.clone();
    emit ProxyCreated(proxy);
    return proxy;
  }
}