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
    function burn(address to) external returns (uint amount0, uint amount1);
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

    struct VaultRegistry {
        address[] tokens;
        bool retired;
        uint block;
        uint256 index;
    }

    mapping (address => VaultRegistry) private _vaultInfo;
    mapping (address => EnumerableSetUpgradeable.AddressSet) private _vaultTokens;

    EnumerableSetUpgradeable.AddressSet private _vaultIndex;

    event VaultsRegistered(address[] vaults);

    function getVaultCount() public view returns(uint256 count) {
        return _vaultIndex.length();
    }

    function intialize() public initializer {
        __Ownable_init();
        //addVault(0xa4918a9B3CE89c3A179Ea873A45a901a4535eC65);
    }

    function addVaults(address[] memory _vaultAddresses) external {
        for (uint i; i < _vaultAddresses.length; i++) {
            IVault vault = IVault(_vaultAddresses[i]);
            IStrategy strat;
           // console.log("Added vault is %s", i);

            require(!_isVault(_vaultAddresses[i]), "Vault Exists");

           // console.log('Validating vault');
            strat = _validateVault(vault);

            address[] memory tokens = _collectTokenData(strat);

          //  console.log('Adding vault to Index');
            _vaultIndex.add(_vaultAddresses[i]);

            for (uint8 token_id = 0; token_id < tokens.length; token_id++) {
               // console.log('Adding vault to token %s', tokens[token_id]);
                _vaultTokens[tokens[token_id]].add(_vaultAddresses[i]);
            }

            _vaultInfo[_vaultAddresses[i]].tokens = tokens;
            _vaultInfo[_vaultAddresses[i]].block = block.number;
            _vaultInfo[_vaultAddresses[i]].index = _vaultIndex.length() - 1; 
        }

        emit VaultsRegistered(_vaultAddresses);
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

    function _isVault(address _address) internal view returns (bool isVault) {
        if (_vaultIndex.length() == 0) return false;
        return (_vaultIndex.contains(_address));
    }

    function getVaultInfo(address _vaultAddress) external view returns (IStrategy strategy, bool isPaused, address[] memory tokens) {
        require(_isVault(_vaultAddress), "Invalid Vault Address");

        IVault vault;
        IStrategy strat;

        tokens = _vaultInfo[_vaultAddress].tokens;
        vault = IVault(_vaultAddress);
        strat = IStrategy(vault.strategy());
        isPaused = strat.paused();

        return (strat, isPaused, tokens);
    }

    function allVaultAddresses() public view returns (address[] memory) {
        return _vaultIndex.values();
    }

    function getVaultsForToken(address _token) external view returns (VaultRegistry[] memory) {
        VaultRegistry[] memory vaultResults = new VaultRegistry[](_vaultTokens[_token].length());

        for (uint256 i; i < _vaultTokens[_token].length(); i++) {
            VaultRegistry storage _vault = _vaultInfo[_vaultTokens[_token].at(i)];
            vaultResults[i] = _vault;
        }

        return vaultResults;
    }

    function getStakedVaultsForAddress(address _address) external view returns (VaultRegistry[] memory) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vid; vid < _vaultIndex.length(); vid++) {
            if (IVault(_vaultIndex.at(vid)).balanceOf(_address) > 0) {
                numResults++;
            }
        }

        VaultRegistry[] memory stakedVaults = new VaultRegistry[](numResults);
        for (uint256 vid; vid < _vaultIndex.length(); vid++) {
            if (IVault(_vaultIndex.at(vid)).balanceOf(_address) > 0) {
                stakedVaults[curResults++] = _vaultInfo[_vaultIndex.at(vid)];
            }
        }

        return stakedVaults;
    }

    function getVaultsAfterBlock(uint256 _block) external view returns (VaultRegistry[] memory) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vid; vid < _vaultIndex.length(); vid++) {
            if (_vaultInfo[_vaultIndex.at(0)].block >= _block) {
                numResults++;
            }
        }

        VaultRegistry[] memory vaultResults = new VaultRegistry[](numResults);
        for (uint256 vid; vid < _vaultIndex.length(); vid++) {
            if (_vaultInfo[_vaultIndex.at(0)].block >= _block) {
                vaultResults[curResults++] = _vaultInfo[_vaultIndex.at(vid)];
            }
        }

        return vaultResults;
    }

    function addTokensToVault(address _vault, address[] memory _tokens) external onlyOwner {
        _vaultInfo[_vault].tokens = _tokens;
    }

    function setRetireStatus(address _address, bool _status) external onlyOwner {
        require(_isVault(_address), "Not our Vault");

        _vaultInfo[_address].retired = _status;
    }
}