// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./ManageableUpgradeable.sol";

import "../interfaces/IBeefyVault.sol";
import "../interfaces/IBeefyStrategy.sol";
import "../interfaces/IBeefyRegistry.sol";

contract BeefyRegistry is ManageableUpgradeable, IBeefyRegistry {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    struct VaultInfo {
        address[] tokens;
        bool retired;
        uint256 blockNumber;
        uint256 index;
    }

    EnumerableSetUpgradeable.AddressSet private _vaultSet;
    mapping(address => VaultInfo) private _vaultInfoMap;
    mapping(address => EnumerableSetUpgradeable.AddressSet) private _tokenToVaultsMap;
    mapping(address => uint256) private _harvestFunctionGasOverhead;

    event VaultsRegistered(address[] vaults_);
    event VaultsRetireStatusUpdated(address[] vaults_, bool status_);
    event VaultHarvestFunctionGasOverheadUpdated(address indexed vaultAddress_, uint256 gasOverhead_);

    function getVaultCount() external view override returns (uint256 count) {
        return _vaultSet.length();
    }

    function initialize() public initializer {
        __Manageable_init();
    }

    function addVaults(address[] memory _vaultAddresses) external onlyManager {
        for (uint256 i; i < _vaultAddresses.length; i++) {
            _addVault(_vaultAddresses[i]);
        }
        emit VaultsRegistered(_vaultAddresses);
    }

    function _addVault(address _vaultAddress) internal {
        require(!_isVaultInRegistry(_vaultAddress), "Vault Exists");

        IBeefyVault vault = IBeefyVault(_vaultAddress);
        IBeefyStrategy strat = _validateVault(vault);

        address[] memory tokens = _collectTokenData(strat);

        _vaultSet.add(_vaultAddress);

        for (uint8 tokenId = 0; tokenId < tokens.length; tokenId++) {
            _tokenToVaultsMap[tokens[tokenId]].add(_vaultAddress);
        }

        _vaultInfoMap[_vaultAddress].tokens = tokens;
        _vaultInfoMap[_vaultAddress].blockNumber = block.number;
        _vaultInfoMap[_vaultAddress].index = _vaultSet.length() - 1;
    }

    function _validateVault(IBeefyVault _vault) internal view returns (IBeefyStrategy strategy) {
        address vaultAddress = address(_vault);

        try _vault.strategy() returns (IBeefyStrategy _strategy) {
            require(IBeefyStrategy(_strategy).vault() == vaultAddress, "Vault/Strat Mismatch");
            return IBeefyStrategy(_strategy);
        } catch {
            require(false, "Address not a Vault");
        }
    }

    function _collectTokenData(IBeefyStrategy _strategy) internal view returns (address[] memory tokens) {
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

    function getVaultInfo(address _vaultAddress)
        external
        view
        returns (
            string memory name_,
            IBeefyStrategy strategy_,
            bool isPaused_,
            address[] memory tokens_,
            uint256 blockNumber_,
            bool retired_,
            uint256 gasOverhead_
        )
    {
        require(_isVaultInRegistry(_vaultAddress), "Invalid Vault Address");

        IBeefyVault vault = IBeefyVault(_vaultAddress);
        VaultInfo memory vaultInfo = _vaultInfoMap[_vaultAddress];

        name_ = vault.name();
        strategy_ = IBeefyStrategy(vault.strategy());
        isPaused_ = strategy_.paused();
        tokens_ = vaultInfo.tokens;
        blockNumber_ = vaultInfo.blockNumber;
        retired_ = vaultInfo.retired;
        gasOverhead_ = _harvestFunctionGasOverhead[_vaultAddress];
    }

    function allVaultAddresses() external view override returns (address[] memory) {
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
            if (IBeefyVault(_vaultSet.at(vid)).balanceOf(_address) > 0) {
                numResults++;
            }
        }

        stakedVaults = new VaultInfo[](numResults);
        for (uint256 vid; vid < _vaultSet.length(); vid++) {
            if (IBeefyVault(_vaultSet.at(vid)).balanceOf(_address) > 0) {
                stakedVaults[curResults++] = _vaultInfoMap[_vaultSet.at(vid)];
            }
        }
    }

    function getVaultsAfterBlock(uint256 _block) external view returns (VaultInfo[] memory vaultResults) {
        uint256 curResults;
        uint256 numResults;

        for (uint256 vaultIndex; vaultIndex < _vaultSet.length(); vaultIndex++) {
            if (_vaultInfoMap[_vaultSet.at(vaultIndex)].blockNumber >= _block) {
                numResults++;
            }
        }

        vaultResults = new VaultInfo[](numResults);
        for (uint256 vaultIndex; vaultIndex < _vaultSet.length(); vaultIndex++) {
            VaultInfo memory vaultInfo = _vaultInfoMap[_vaultSet.at(vaultIndex)];
            if (vaultInfo.blockNumber >= _block) {
                vaultResults[curResults++] = vaultInfo;
            }
        }
    }

    function setVaultTokens(address _vault, address[] memory _tokens) external onlyManager {
        address[] memory currentTokens = _vaultInfoMap[_vault].tokens;

        // remove all old mapping of token to vault
        for (uint256 tokenIndex; tokenIndex < currentTokens.length; tokenIndex++) {
            _tokenToVaultsMap[_tokens[tokenIndex]].remove(_vault);
        }

        // update struct tokens
        _vaultInfoMap[_vault].tokens = _tokens;

        // update token to vault mapping with new tokens
        for (uint256 tokenIndex; tokenIndex < _tokens.length; tokenIndex++) {
            _tokenToVaultsMap[_tokens[tokenIndex]].add(_vault);
        }
    }

    function setRetireStatuses(address[] memory _vaultAddresses, bool _status) external onlyManager {
        for (uint256 vaultIndex = 0; vaultIndex < _vaultAddresses.length; vaultIndex++) {
            _setRetireStatus(_vaultAddresses[vaultIndex], _status);
        }
        emit VaultsRetireStatusUpdated(_vaultAddresses, _status);
    }

    function _setRetireStatus(address _address, bool _status) internal {
        require(_isVaultInRegistry(_address), "Vault not found in registry.");
        _vaultInfoMap[_address].retired = _status;
    }

    function setHarvestFunctionGasOverhead(address vaultAddress_, uint256 gasOverhead_) external override onlyManager {
        require(_isVaultInRegistry(vaultAddress_), "Vault not found in registry.");
        _harvestFunctionGasOverhead[vaultAddress_] = gasOverhead_;

        emit VaultHarvestFunctionGasOverheadUpdated(vaultAddress_, gasOverhead_);
    }

    /**
     * @dev Rescues random funds stuck.
     * @param token_ address of the token to rescue.
     */
    function inCaseTokensGetStuck(address token_) external onlyManager {
        IERC20Upgradeable token = IERC20Upgradeable(token_);

        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, amount);
    }
}
