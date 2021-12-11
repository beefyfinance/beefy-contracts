// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "../interfaces/beefy/IBeefyRegistryVault.sol";
import "../interfaces/beefy/IBeefyRegistryStrategy.sol";


contract BeefyVaultRegistry is Initializable, OwnableUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    struct VaultInfo {
        address[] tokens;
        bool retired;
        uint256 blockNumber;
        uint256 index;
    }

    EnumerableSetUpgradeable.AddressSet private _vaultSet;

    mapping (address => VaultInfo) private _vaultInfoMap;
    mapping (address => EnumerableSetUpgradeable.AddressSet) private _tokenToVaultsMap;

    event VaultsRegistered(address[] vaults);
    event VaultsRetired(address[] vaults);

    function getVaultCount() external view returns(uint256 count) {
        return _vaultSet.length();
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function addVaults(address[] memory _vaultAddresses) external onlyOwner {
        for (uint256 i; i < _vaultAddresses.length; i++) {
            _addVault(_vaultAddresses[i]);
        }
        emit VaultsRegistered(_vaultAddresses);
    }


    function _addVault(address _vaultAddress) internal {
            require(!_isVaultInRegistry(_vaultAddress), "Vault Exists");

            IBeefyRegistryVault vault = IBeefyRegistryVault(_vaultAddress);
            IBeefyRegistryStrategy strat = _validateVault(vault);

            address[] memory tokens = _collectTokenData(strat);

            _vaultSet.add(_vaultAddress);

            for (uint8 token_id = 0; token_id < tokens.length; token_id++) {
                _tokenToVaultsMap[tokens[token_id]].add(_vaultAddress);
            }

            _vaultInfoMap[_vaultAddress].tokens = tokens;
            _vaultInfoMap[_vaultAddress].blockNumber = block.number;
            _vaultInfoMap[_vaultAddress].index = _vaultSet.length() - 1; 
    }

    function _validateVault(IBeefyRegistryVault _vault) internal view returns (IBeefyRegistryStrategy strategy) {
        address vaultAddress = address(_vault);

        try _vault.strategy() returns (IBeefyRegistryStrategy _strategy) {
            require(IBeefyRegistryStrategy(_strategy).vault() == vaultAddress, "Vault/Strat Mismatch");
            return IBeefyRegistryStrategy(_strategy);
        } catch {
            require(false, "Address not a Vault");
        }
    }

    function _collectTokenData(IBeefyRegistryStrategy _strategy) internal view returns (address[] memory tokens) {
        try _strategy.lpToken0() returns (address lpToken0) {
            tokens = new address[](3);

            tokens[0] = address(_strategy.want());
            tokens[1] = address(lpToken0);
            tokens[2] = address(_strategy.lpToken1());
        } catch (bytes memory) {
            tokens = new address[](1);

            tokens[0] = address(_strategy.want());
        }
    }

    function _isVaultInRegistry(address _address) internal view returns (bool isVault) {
        if (_vaultSet.length() == 0) return false;
        return (_vaultSet.contains(_address));
    }

    function getVaultInfo(address _vaultAddress) external view returns (string memory name, IBeefyRegistryStrategy strategy, bool isPaused, address[] memory tokens, uint256 blockNumber, bool retired) {
        require(_isVaultInRegistry(_vaultAddress), "Invalid Vault Address");

        IBeefyRegistryVault vault = IBeefyRegistryVault(_vaultAddress);

        name = vault.name();
        strategy = IBeefyRegistryStrategy(vault.strategy());
        isPaused = strategy.paused();
        
        VaultInfo memory vaultInfo = _vaultInfoMap[_vaultAddress];
        tokens = vaultInfo.tokens;
        blockNumber = vaultInfo.blockNumber;
        retired = vaultInfo.retired;
    }

    function allVaultAddresses() external view returns (address[] memory) {
        return _vaultSet.values();
    }

    function getVaultsForToken(address _token) external view returns (VaultInfo[] memory vaultResults) {
        vaultResults = new VaultInfo[](_tokenToVaultsMap[_token].length());
        for (uint256 i; i < _tokenToVaultsMap[_token].length(); i++) {
            VaultInfo memory _vault = _vaultInfoMap[_tokenToVaultsMap[_token].at(i)];
            vaultResults[i] = _vault;
        }
    }

    function getStakedVaultsForAddress(address _address) external view returns (VaultInfo[] memory stakedVaults) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (IBeefyRegistryVault(_vaultSet.at(vid)).balanceOf(_address) > 0) {
                numResults++;
            }
        }

        stakedVaults = new VaultInfo[](numResults);
        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (IBeefyRegistryVault(_vaultSet.at(vid)).balanceOf(_address) > 0) {
                stakedVaults[curResults++] = _vaultInfoMap[_vaultSet.at(vid)];
            }
        }
    }

    function getVaultsAfterBlock(uint256 _block) external view returns (VaultInfo[] memory vaultResults) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (_vaultInfoMap[_vaultSet.at(0)].blockNumber >= _block) {
                numResults++;
            }
        }

        vaultResults = new VaultInfo[](numResults);
        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (_vaultInfoMap[_vaultSet.at(0)].blockNumber >= _block) {
                vaultResults[curResults++] = _vaultInfoMap[_vaultSet.at(vid)];
            }
        }
    }

    function addTokensToVault(address _vault, address[] memory _tokens) external onlyOwner {
        _vaultInfoMap[_vault].tokens = _tokens;
    }

    function setRetireStatus(address _address, bool _status) external onlyOwner {
        require(_isVaultInRegistry(_address), "Vault not found in registry.");
        _vaultInfoMap[_address].retired = _status;
    }
}
