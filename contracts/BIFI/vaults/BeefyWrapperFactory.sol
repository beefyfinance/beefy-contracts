// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BeefyWrapper.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

interface IWrapper {
  function initialize(address _vault, string memory _name, string memory _symbol) external;
}

// Beefy Wrapper Proxy Factory
// Minimal proxy pattern for creating new Beefy Vault wrappers
contract BeefyWrapperFactory {
  using ClonesUpgradeable for address;

  // Contract template for deploying proxied Beefy Vault wrappers
  address public immutable implementation;

  event ProxyCreated(address proxy);

  // Initializes the Factory with an instance of the Beefy Vault Wrapper
  constructor() {
    implementation = address(new BeefyWrapper());
  }

  // Creates a new Beefy Vault wrapper as a proxy of the template instance
  // @param _vault reference to the cloned Beefy Vault
  // @return proxy reference to the new proxied Beefy Vault wrapper
  function clone(
    address _vault
  ) external returns (address proxy) {
    proxy = implementation.clone();
    IWrapper(proxy).initialize(
      _vault,
      string.concat("W", IVault(_vault).name()),
      string.concat("w", IVault(_vault).symbol())
    );
    emit ProxyCreated(proxy);
  }
}
