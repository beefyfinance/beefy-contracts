// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/beefy/IBeefyVault.sol";
import "../interfaces/beefy/IBeefyStrategy.sol";

contract BeefyRegistry is Initializable {
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

  event VaultAdded(address vault);
  event ProposedGovernance(address governance);
  event SwitchedGovernance(address oldGovernance, address newGovernance);

  address public governance;  
  address public pendingGovernance;

  EnumerableSetUpgradeable.AddressSet private vaults;

  function intialize(address _governance) public initializer {
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
    address strategy,
    uint256 lastHarvest,
    bool harvestOnDeposit,
    uint256 callRewards
  ) {
    IBeefyVault vault = IBeefyVault(_vault);
    want = address(vault.want());
    strategy = address(vault.strategy());
    lastHarvest = IBeefyStrategy(strategy).lastHarvest();
    harvestOnDeposit = IBeefyStrategy(strategy).harvestOnDeposit();
    callRewards = IBeefyStrategy(strategy).callRewards();
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
    address strategy,
    uint256 lastHarvest,
    bool harvestOnDeposit,
    uint256 callRewards
  ) {
    (want, strategy, lastHarvest, harvestOnDeposit, callRewards) = getVaultData(_vault);
  }

 // function getVaultsInfo() external view returns (
 //   address[] memory wantArray,
 //   address[] memory strategyArray
 // ) {
 //   wantArray = new address[](vaults.length());
 //   strategyArray = new address[](vaults.length());
 //   
 //   for (uint i = 0; i < vaults.length(); i++) {
 //     (address _want, address _strategy) = getVaultData(vaults.at(i));
 //     wantArray[i] = _want;
 //     strategyArray[i] = _strategy;
 //   }
 // }

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