// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./ManageableUpgradeable.sol";

import "../interfaces/IBeefyRegistry.sol";
import "../interfaces/IBeefyVault.sol";
import "../interfaces/IBeefyStrategy.sol";
import "../interfaces/IVaultGasOverheadAnalyzer.sol";

import "../libraries/UpkeepLibrary.sol";

contract VaultGasOverheadAnalyzer is ManageableUpgradeable, IVaultGasOverheadAnalyzer {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    EnumerableSetUpgradeable.AddressSet private _upkeepers;

    IBeefyRegistry private _vaultRegistry;

    uint256 private _index;
    uint256 private _lastUpdateCycle; // Last time all harvestGasOverhead were updated in vault array.
    address private _dummyCallFeeRecipient;

    modifier onlyUpkeeper() {
        require(_upkeepers.contains(msg.sender), "!upkeeper");
        _;
    }

    function initialize() public initializer {
        __Manageable_init();

        _dummyCallFeeRecipient = address(this);
    }

    /*             */
    /* checkUpkeep */
    /*             */

    function checkUpkeep(
        bytes calldata checkData_ // unused
    )
        external
        view
        override
        returns (
            bool upkeepNeeded_,
            bytes memory performData_ // array of vaults +
        )
    {
        checkData_; // dummy reference to get rid of unused parameter warning

        // Get all vault addresses.
        address[] memory vaults = _vaultRegistry.allVaultAddresses();

        // Get vault to analyze.
        IBeefyVault vaultToAnalyze = IBeefyVault(vaults[_index]);

        // Update index
        uint256 newIndex = UpkeepLibrary._getCircularIndex(_index, 1, vaults.length);

        if (newIndex == 0) {
            // We've hit the start, restart delay in cron job
        }
    }

    function _analyzeHarvest(address vault) internal returns (bool didHarvest_, uint256 gasOverhead_) {
        IBeefyStrategy strategy = IBeefyStrategy(IBeefyVault(vault).strategy());

        (bool didHarvest, uint256 gasOverhead) = _tryHarvest(strategy);

        if (didHarvest) {
            return (didHarvest, gasOverhead);
        }

        // Try old function signature.

        (didHarvest, gasOverhead) = _tryOldHarvest(strategy);

        if (didHarvest) {
            return (didHarvest, gasOverhead);
        }

        // Both failed, report failure.

        return (false, 0);
    }

    function _tryHarvest(IBeefyStrategy strategy) internal returns (bool didHarvest_, uint256 gasOverhead_) {
        uint256 gasBefore = gasleft();
        try strategy.harvest(_dummyCallFeeRecipient) {
            didHarvest_ = true;
            /* solhint-disable no-empty-blocks */
        } catch {
            /* solhint-enable no-empty-blocks */
        }

        uint256 gasAfter = gasleft();
        gasOverhead_ = gasBefore - gasAfter;
    }

    function _tryOldHarvest(IBeefyStrategy strategy) internal returns (bool didHarvest_, uint256 gasOverhead_) {
        uint256 gasBefore = gasleft();
        try strategy.harvestWithCallFeeRecipient(_dummyCallFeeRecipient) {
            didHarvest_ = true;
            /* solhint-disable no-empty-blocks */
        } catch {
            /* solhint-enable no-empty-blocks */
        }

        uint256 gasAfter = gasleft();
        gasOverhead_ = gasBefore - gasAfter;
    }

    /*               */
    /* performUpkeep */
    /*               */

    function performUpkeep(bytes calldata performData) external override onlyUpkeeper {
        (
            address[] memory vaultsToHarvest,
            uint256 newStartIndex,
            uint256 heuristicEstimatedTxCost,
            uint256 nonHeuristicEstimatedTxCost,
            uint256 estimatedCallRewards
        ) = abi.decode(performData, (address[], uint256, uint256, uint256, uint256));

        _runUpkeep(
            
        );
    }

    function _runUpkeep() internal {}

    /*     */
    /* Set */
    /*     */

    function setUpkeepers(address[] memory upkeepers_, bool status_) external override onlyManager {
        for (uint256 upkeeperIndex = 0; upkeeperIndex < upkeepers_.length; upkeeperIndex++) {
            _setUpkeeper(upkeepers_[upkeeperIndex], status_);
        }
    }

    function _setUpkeeper(address upkeeper_, bool status_) internal {
        if (status_) {
            _upkeepers.add(upkeeper_);
        } else {
            _upkeepers.remove(upkeeper_);
        }
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
