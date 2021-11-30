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
        uint256 block;
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
        //addVault(0xa4918a9B3CE89c3A179Ea873A45a901a4535eC65);
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

       // console.log('_validateVault address %s', address(_vault));
        try _vault.strategy() returns (IStrategy _strategy) {
            require(IStrategy(_strategy).vault() == vaultAddress, "Vault/Strat Mismatch");
           // console.log('Strategy address is %s', address(_strategy));
            return IStrategy(_strategy);
        } catch {
            require(false, "Address not a Vault");
        }
    }

    function _collectTokenData(IStrategy _strategy) internal view returns (address[] memory) {
        try _strategy.lpToken0() returns (address lpToken0) {
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
    }

    function _isVaultInRegistry(address _address) internal view returns (bool isVault) {
        if (_vaultSet.length() == 0) return false;
        return (_vaultSet.contains(_address));
    }

    function getVaultInfo(address _vaultAddress) external view returns (IStrategy strategy, bool isPaused, address[] memory tokens) {
        require(_isVaultInRegistry(_vaultAddress), "Invalid Vault Address");

        IVault vault;
        IStrategy strat;

        tokens = _vaultInfoMap[_vaultAddress].tokens;
        vault = IVault(_vaultAddress);
        strat = IStrategy(vault.strategy());
        isPaused = strat.paused();

        return (strat, isPaused, tokens);
    }

    function allVaultAddresses() public view returns (address[] memory) {
        return _vaultSet.values();
    }

    function getVaultsForToken(address _token) external view returns (VaultInfo[] memory) {
        VaultInfo[] memory vaultResults = new VaultInfo[](_vaultTokens[_token].length());

        for (uint256 i; i < _vaultTokens[_token].length(); i++) {
            VaultInfo storage _vault = _vaultInfoMap[_vaultTokens[_token].at(i)];
            vaultResults[i] = _vault;
        }

        return vaultResults;
    }

    function getStakedVaultsForAddress(address _address) external view returns (VaultInfo[] memory) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (IVault(_vaultSet.at(vid)).balanceOf(_address) > 0) {
                numResults++;
            }
        }

        VaultInfo[] memory stakedVaults = new VaultInfo[](numResults);
        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (IVault(_vaultSet.at(vid)).balanceOf(_address) > 0) {
                stakedVaults[curResults++] = _vaultInfoMap[_vaultSet.at(vid)];
            }
        }

        return stakedVaults;
    }

    function getVaultsAfterBlock(uint256 _block) external view returns (VaultInfo[] memory) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (_vaultInfoMap[_vaultSet.at(0)].block >= _block) {
                numResults++;
            }
        }

        VaultInfo[] memory vaultResults = new VaultInfo[](numResults);
        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (_vaultInfoMap[_vaultSet.at(0)].block >= _block) {
                vaultResults[curResults++] = _vaultInfoMap[_vaultSet.at(vid)];
            }
        }

        return vaultResults;
    }

    function addTokensToVault(address _vault, address[] memory _tokens) external onlyOwner {
        _vaultInfoMap[_vault].tokens = _tokens;
    }

    function setRetireStatus(address _address, bool _status) external onlyOwner {
        require(_isVaultInRegistry(_address), "Vault not found in registry.");
        _vaultInfoMap[_address].retired = _status;
    }
}
