// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/beefy/IVault.sol";

contract BeefyRegistry {
  using Address for address;
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  event VaultAdded(address vault);
  event ProposedGovernance(address governance);
  event SwitchedGovernance(address oldGovernance, address newGovernance);

  address public governance;  
  address public pendingGovernance;

  EnumerableSet.AddressSet private vaults;

  constructor(address _governance) {
    require(_governance != address(0), "!gov");
    governance = _governance;
  }

  function getName() external pure returns (string memory) {
    return "BeefyRegistry";
  }

  function addVault(address _vault) public onlyGovernance {
    setVault(_vault);
  }

  function setVault(address _vault) internal {
    require(_vault.isContract(), "!contract");
    require(!vaults.contains(_vault), "!duplicated");
    vaults.add(_vault);
    emit VaultAdded(_vault);
  }
  
  function getVaultData(address _vault) internal view returns (
    address want,
    address strategy
  ) {
    IVault vault = IVault(_vault);
    want = address(vault.want());
    strategy = address(vault.strategy());
    return (want, strategy);
  }

  // Vaults getters
  function getVault(uint index) external view returns (address vault) {
    return vaults.at(index);
  }

  function getVaultsLength() external view returns (uint) {
    return vaults.length();
  }

  function getVaults() external view returns (address[] memory) {
    address[] memory vaultsArray = new address[](vaults.length());
    for (uint i = 0; i < vaults.length(); i++) {
      vaultsArray[i] = vaults.at(i);
    }
    return vaultsArray;
  }

  function getVaultInfo(address _vault) external view returns (
    address want,
    address strategy
  ) {
    (want, strategy) = getVaultData(_vault);
    return (
      want,
      strategy
    );
  }

  function getVaultsInfo() external view returns (
    address[] memory wantArray,
    address[] memory strategyArray
  ) {
    wantArray = new address[](vaults.length());
    strategyArray = new address[](vaults.length());
    
    for (uint i = 0; i < vaults.length(); i++) {
      (address _want, address _strategy) = getVaultData(vaults.at(i));
      wantArray[i] = _want;
      strategyArray[i] = _strategy;
    }
  }

 // Governance setters
  function setPendingGovernance(address _pendingGovernance) external onlyGovernance {
    pendingGovernance = _pendingGovernance;
    emit ProposedGovernance(_pendingGovernance);
  }
  
  function acceptGovernance() external onlyPendingGovernance {
    emit SwitchedGovernance(governance, msg.sender);
    governance = pendingGovernance;
  }

  modifier onlyGovernance {
    require(msg.sender == governance, "!gov");
    _;
  }
  
  modifier onlyPendingGovernance {
    require(msg.sender == pendingGovernance, "!pending");
    _;
  }
}