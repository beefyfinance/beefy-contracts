// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IUniswapV2Pair {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IStrategy {
    function vault() external view returns (address);
    function want() external view returns (IERC20Upgradeable);
    function beforeDeposit() external;
    function deposit() external;
    function withdraw(uint256) external;
    function balanceOf() external view returns (uint256);
    function balanceOfWant() external view returns (uint256);
    function balanceOfPool() external view returns (uint256);
    function harvest() external;
    function retireStrat() external;
    function panic() external;
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
    function unirouter() external view returns (address);
    function lpToken0() external view returns (address);
    function lpToken1() external view returns (address);
}

interface IVault is IERC20Upgradeable {
    function deposit(uint256) external;
    function depositAll() external;
    function withdraw(uint256) external;
    function withdrawAll() external;
    function getPricePerFullShare() external view returns (uint256);
    function upgradeStrat() external;
    function balance() external view returns (uint256);
    function want() external view returns (IERC20Upgradeable);
    function strategy() external view returns (IStrategy);
}

contract BeefyVaultRegistry is Initializable, OwnableUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    struct VaultInfo {
        EnumerableSetUpgradeable.AddressSet tokens;
        bool retired;
        uint blockNumber;
        uint256 index;
    }

    EnumerableSetUpgradeable.AddressSet private _vaultSet;
    mapping (address => VaultInfo) private _vaultInfoMap;

    event VaultsRegistered(address[] vaults);
    event VaultsRetired(address[] vaults);

    function getVaultCount() public view returns(uint256 count) {
        return _vaultSet.length();
    }

    function intialize() public initializer {
        __Ownable_init();
    }

    function addVaults(address[] memory _vaultAddresses) external {
        for (uint256 i; i < _vaultAddresses.length; i++) {
            _addVault(_vaultAddresses[i]);
        }
        emit VaultsRegistered(_vaultAddresses);
    }


    function _addVault(address _vaultAddress) internal {
            require(!_isVaultInRegistry(_vaultAddresses[i]), "Vault Exists");

            IVault vault = IVault(_vaultAddresses[i]);
            IStrategy strat = _validateVault(vault);

            address[] memory tokens = _collectTokenData(strat);

            _vaultSet.add(_vaultAddresses[i]);

            for (uint8 token_id = 0; token_id < tokens.length; token_id++) {
                _vaultTokens[tokens[token_id]].add(_vaultAddresses[i]);
            }

            _vaultInfoMap[_vaultAddresses[i]].tokens = tokens;
            _vaultInfoMap[_vaultAddresses[i]].block = block.number;
            _vaultInfoMap[_vaultAddresses[i]].index = _vaultSet.length() - 1; 
    }

    function _validateVault(IVault _vault) internal view returns (IStrategy strategy) {
        address vaultAddress = address(_vault);

        try _vault.strategy() returns (IStrategy _strategy) {
            require(IStrategy(_strategy).vault() == vaultAddress, "Vault/Strat Mismatch");
            return IStrategy(_strategy);
        } catch {
            require(false, "Address not a Vault");
        }
    }

    function _collectTokenData(IStrategy _strategy) internal view returns (address[] memory tokens) {
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

    function getVaultInfo(address _vaultAddress) external view returns (IStrategy strategy, bool isPaused, address[] memory tokens) {
        require(_isVaultInRegistry(_vaultAddress), "Invalid Vault Address");

        tokens = _vaultInfo[_vaultAddress].tokens;
        IVault vault = IVault(_vaultAddress);
        strategy = IStrategy(vault.strategy());
        isPaused = strategy.paused();
    }

    function allVaultAddresses() public view returns (address[] memory) {
        return _vaultSet.values();
    }

    function getVaultsForToken(address _token) external view returns (VaultInfo[] memory vaultResults) {
        VaultInfo[] memory vaultResults = new VaultInfo[](_vaultTokens[_token].length());
        vaultResults = new VaultInfo[](_vaultTokens[_token].length());

        for (uint256 i; i < _vaultTokens[_token].length(); i++) {
            VaultInfo storage _vault = _vaultInfoMap[_vaultTokens[_token].at(i)];
            vaultResults[i] = _vault;
        }
    }

    function getStakedVaultsForAddress(address _address) external view returns (VaultInfo[] memory stakedVaults) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (IVault(_vaultSet.at(vid)).balanceOf(_address) > 0) {
                numResults++;
            }
        }

        stakedVaults = new VaultInfo[](numResults);
        for (uint256 vid; vid < _vaultIndex.length(); vid++) {
            if (IVault(_vaultIndex.at(vid)).balanceOf(_address) > 0) {
                stakedVaults[curResults++] = _vaultInfo[_vaultIndex.at(vid)];
            }
        }
    }

    function getVaultsAfterBlock(uint256 _block) external view returns (VaultInfo[] memory vaultResults) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vid; vid < _vaultIndex.length(); vid++) {
            if (_vaultInfo[_vaultIndex.at(0)].blockNumber >= _block) {
                numResults++;
            }
        }

        vaultResults = new VaultInfo[](numResults);
        for (uint256 vid; vid < _vaultIndex.length(); vid++) {
            if (_vaultInfo[_vaultIndex.at(0)].blockNumber >= _block) {
                vaultResults[curResults++] = _vaultInfo[_vaultIndex.at(vid)];
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
