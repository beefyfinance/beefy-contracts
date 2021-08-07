// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/common/IUniswapV2Pair.sol";
import "../interfaces/beefy/IStrategy.sol";
import "../interfaces/beefy/IVault.sol";

contract BeefyVaultRegistry {

    struct VaultRegistry {
        IERC20[] tokens;
        uint block;
        uint256 index;
    }

    mapping (address => VaultRegistry) private _vaultInfo;

    address[] private _vaultIndex;

    event VaultRegistered(address vault);

    function getVaultCount() public view returns(uint256 count) {
        return _vaultIndex.length;
    }

    constructor() public {
        //addVault(0xa4918a9B3CE89c3A179Ea873A45a901a4535eC65);
    }

    function addVault(address _vaultAddress) public {
        IVault vault = IVault(_vaultAddress);
        IStrategy strat;

        require(!_isVault(_vaultAddress), "Vault Exists");

        strat = _validateVault(vault);

        IERC20[] memory tokens = _collectTokenData(strat);

        _vaultIndex.push(_vaultAddress);

        _vaultInfo[_vaultAddress].tokens = tokens;
        _vaultInfo[_vaultAddress].block = block.number;
        _vaultInfo[_vaultAddress].index = _vaultIndex.length - 1;

        emit VaultRegistered(_vaultAddress);
    }

    function _validateVault(IVault _vault) internal view returns (IStrategy strategy) {
        address vaultAddress = address(_vault);

        try _vault.strategy() returns (address _strategy) {
            require(IStrategy(_strategy).vault() == vaultAddress, "Vault/Strat Mismatch");

            return IStrategy(_strategy);
        } catch {
            require(false, "Address not a Vault");
        }
    }

    function _collectTokenData(IStrategy _strategy) internal view returns (IERC20[] memory) {
        uint8 numTokens = 1;
        IERC20 want;

        try _strategy.lpToken0() {
            numTokens = 2;
        } catch {
            want = IERC20(_strategy.want());
        }

        IERC20[] memory tokens = new IERC20[](numTokens);

        if (numTokens == 2) {
            tokens[0] = _strategy.lpToken0();
            tokens[1] = _strategy.lpToken1();
        } else {
            tokens[0] = want;
        }

        return tokens;
    }

    function _isVault(address _vaultAddress) internal view returns (bool isVault) {
        if (_vaultIndex.length == 0) return false;
        return (_vaultIndex[_vaultInfo[_vaultAddress].index] == _vaultAddress);
    }

    function getVault(address _vaultAddress) public view returns (address strategy, bool isPaused, IERC20[] memory tokens) {
        require(_isVault(_vaultAddress), "Invalid Vault Address");

        IVault vault;
        IStrategy strat;

        tokens = _vaultInfo[_vaultAddress].tokens;
        vault = IVault(_vaultAddress);
        strat = IStrategy(vault.strategy());
        isPaused = strat.paused();

        return (vault.strategy(), isPaused, tokens);
    }

    // function allVaults() public view returns (address[] memory) {
    //     address[] memory vaultResults = new address[](_vaultInfo.length);

    //     for (uint256 vid = 0; vid < _vaultInfo.length; vid++) {
    //         vaultResults[vid] = _vaultInfo[vid].vaultAddress;
    //     }

    //     return (vaultResults);
    // }

    function getVaultsForToken(IERC20 _token) public view returns (address[] memory) {
        uint256 curResults = 0;
        uint256 numResults = 0;

        for (uint256 vid = 0; vid < _vaultIndex.length; vid++) {
            for (uint t = 0; t < _vaultInfo[_vaultIndex[vid]].tokens.length; t++) {
                if (_vaultInfo[_vaultIndex[vid]].tokens[t] == _token) {
                    numResults++;
                }
            }
        }

        address[] memory vaultResults = new address[](numResults);
        for (uint256 vid = 0; vid < _vaultIndex.length; vid++) {
            for (uint t = 0; t < _vaultInfo[_vaultIndex[vid]].tokens.length; t++) {
                if (_vaultInfo[_vaultIndex[vid]].tokens[t] == _token) {
                    vaultResults[curResults++] = _vaultIndex[vid];
                }
            }
        }

        return vaultResults;
    }

    function getStakedVaultsForAddress(address _address) public view returns (address[] memory) {
        uint256 curResults = 0;
        uint256 numResults = 0;

        for (uint256 vid = 0; vid < _vaultIndex.length; vid++) {
            if (IVault(_vaultIndex[vid]).balanceOf(_address) > 0) {
                numResults++;
            }
        }

        address[] memory stakedVaults = new address[](numResults);
        for (uint256 vid = 0; vid < _vaultIndex.length; vid++) {
            if (IVault(_vaultIndex[vid]).balanceOf(_address) > 0) {
                stakedVaults[curResults++] = _vaultIndex[vid];
            }
        }

        return stakedVaults;
    }
}