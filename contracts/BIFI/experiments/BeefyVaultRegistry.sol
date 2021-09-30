// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interfaces/common/IUniswapV2Pair.sol";
import "../interfaces/beefy/IStrategy.sol";
import "../interfaces/beefy/IVault.sol";

contract BeefyVaultRegistry is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct VaultRegistry {
        address[] tokens;
        bool retired;
        uint block;
        uint256 index;
    }

    mapping (address => VaultRegistry) private _vaultInfo;
    mapping (address => EnumerableSet.AddressSet) private _vaultTokens;

    EnumerableSet.AddressSet private _vaultIndex;

    event VaultRegistered(address vault);

    function getVaultCount() public view returns(uint256 count) {
        return _vaultIndex.length();
    }

    constructor() {
        //addVault(0xa4918a9B3CE89c3A179Ea873A45a901a4535eC65);
    }

    function addVault(address _vaultAddress) external {
        IVault vault = IVault(_vaultAddress);
        IStrategy strat;
        console.log("Added vault is %s", _vaultAddress);

        require(!_isVault(_vaultAddress), "Vault Exists");

        console.log('Validating vault');
        strat = _validateVault(vault);

        address[] memory tokens = _collectTokenData(strat);

        console.log('Adding vault to Index');
        _vaultIndex.add(_vaultAddress);

        for (uint8 token_id = 0; token_id < tokens.length; token_id++) {
            console.log('Adding vault to token %s', tokens[token_id]);
            _vaultTokens[tokens[token_id]].add(_vaultAddress);
        }

        _vaultInfo[_vaultAddress].tokens = tokens;
        _vaultInfo[_vaultAddress].block = block.number;
        _vaultInfo[_vaultAddress].index = _vaultIndex.length() - 1;

        emit VaultRegistered(_vaultAddress);
    }

    function _validateVault(IVault _vault) internal view returns (IStrategy strategy) {
        address vaultAddress = address(_vault);

        console.log('_validateVault address %s', address(_vault));
        try _vault.strategy() returns (address _strategy) {
            require(IStrategy(_strategy).vault() == vaultAddress, "Vault/Strat Mismatch");
            console.log('Strategy address is %s', address(_strategy));
            return IStrategy(_strategy);
        } catch {
            require(false, "Address not a Vault");
        }
    }

    function _collectTokenData(IStrategy _strategy) internal view returns (address[] memory) {
        try _strategy.lpToken0() returns (IERC20 lpToken0) {
            address[] memory tokens = new address[](3);

            tokens[0] = address(_strategy.want());
            tokens[1] = address(lpToken0);
            tokens[2] = address(_strategy.lpToken1());

            return tokens;
        } catch (bytes memory) {
            address[] memory tokens = new address[](1);

            tokens[0] = address(_strategy.want());
            return tokens;
        }

        return tokens;
    }

    function _isVault(address _address) internal view returns (bool isVault) {
        if (_vaultIndex.length() == 0) return false;
        return (_vaultIndex.contains(_address));
    }

    function getVaultInfo(address _vaultAddress) external view returns (address strategy, bool isPaused, address[] memory tokens) {
        require(_isVault(_vaultAddress), "Invalid Vault Address");

        IVault vault;
        IStrategy strat;

        tokens = _vaultInfo[_vaultAddress].tokens;
        vault = IVault(_vaultAddress);
        strat = IStrategy(vault.strategy());
        isPaused = strat.paused();

        return (vault.strategy(), isPaused, tokens);
    }

    function allVaultAddresses() public view returns (address[] memory) {
        return _vaultIndex.values();
    }

    function getVaultsForToken(address _token) external view returns (VaultRegistry[] memory) {
        VaultRegistry[] memory vaultResults = new VaultRegistry[](_vaultTokens[_token].length());

        for (uint256 i = 0; i < _vaultTokens[_token].length(); i++) {
            VaultRegistry storage _vault = _vaultInfo[_vaultTokens[_token].at(i)];
            vaultResults[i] = _vault;
        }

        return vaultResults;
    }

    function getStakedVaultsForAddress(address _address) external view returns (VaultRegistry[] memory) {
        uint256 curResults = 0;
        uint256 numResults = 0;

        for (uint256 vid = 0; vid < _vaultIndex.length(); vid++) {
            if (IVault(_vaultIndex.at(vid)).balanceOf(_address) > 0) {
                numResults++;
            }
        }

        VaultRegistry[] memory stakedVaults = new VaultRegistry[](numResults);
        for (uint256 vid = 0; vid < _vaultIndex.length(); vid++) {
            if (IVault(_vaultIndex.at(vid)).balanceOf(_address) > 0) {
                stakedVaults[curResults++] = _vaultInfo[_vaultIndex.at(vid)];
            }
        }

        return stakedVaults;
    }

    function getVaultsAfterBlock(uint256 block) external view returns (VaultRegistry[] memory) {
        uint256 curResults = 0;
        uint256 numResults = 0;

        for (uint256 vid = 0; vid < _vaultIndex.length(); vid++) {
            if (_vaultInfo[_vaultIndex.at(0)].block >= block) {
                numResults++;
            }
        }

        VaultRegistry[] memory vaultResults = new VaultRegistry[](numResults);
        for (uint256 vid = 0; vid < _vaultIndex.length(); vid++) {
            if (_vaultInfo[_vaultIndex.at(0)].block >= block) {
                vaultResults[curResults++] = _vaultInfo[_vaultIndex.at(vid)];
            }
        }

        return vaultResults;
    }

    function addTokensToVault(address[] _tokens) external onlyOwner {
        return false;
    }

    function retireVault(address _address) external onlyOwner {
        require(_isVault(_address, "Not our Vault"));

        _vaultInfo[_address].retired = true;
    }
}