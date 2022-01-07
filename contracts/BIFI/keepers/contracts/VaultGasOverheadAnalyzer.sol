// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./ManageableUpgradeable.sol";

import "../interfaces/IBeefyRegistry.sol";
import "../interfaces/IBeefyVault.sol";
import "../interfaces/IBeefyStrategyEthCall.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

import "../libraries/UpkeepLibrary.sol";

contract VaultGasOverheadAnalyzer is ManageableUpgradeable, KeeperCompatibleInterface {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    IBeefyRegistry private _vaultRegistry;

    uint256 private _index;
    uint256 private _lastUpdateCycle; // Last time all harvestGasOverhead were updated in vault array.
    address private _dummyCallFeeRecipient;

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

        // Make sure cron is running.
        /* solhint-disable not-rely-on-time */
        uint256 oneWeekAgo = block.timestamp - 1 weeks;
        /* solhint-enable not-rely-on-time */
        if (_lastUpdateCycle > oneWeekAgo) {
            // only run once a week
            return (false, bytes("VaultGasOverheadAnalyzer: Ran less than 1 week ago."));
        } 

        // Get all vault addresses.
        address[] memory vaults = _vaultRegistry.allVaultAddresses();

        // Get current circular index. This also protects against race condition where vault array in registry is edited while cron is running.
        uint256 currentIndex = UpkeepLibrary._getCircularIndex(_index, 0, vaults.length);

        // Get vault to analyze.
        IBeefyVault vaultToAnalyze = IBeefyVault(vaults[currentIndex]);

        ( bool didHarvest, uint256 gasOverhead ) = _analyzeHarvest(vaultToAnalyze);

        performData_ = abi.encode(
            currentIndex,
            didHarvest,
            gasOverhead
        );

        return (true, performData_);
    }

    function _analyzeHarvest(IBeefyVault vault) internal view returns (bool didHarvest_, uint256 gasOverhead_) {
        IBeefyStrategyEthCall strategy = IBeefyStrategyEthCall(address(IBeefyVault(vault).strategy()));

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

    function _tryHarvest(IBeefyStrategyEthCall strategy) internal view returns (bool didHarvest_, uint256 gasOverhead_) {
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

    function _tryOldHarvest(IBeefyStrategyEthCall strategy) internal view returns (bool didHarvest_, uint256 gasOverhead_) {
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

    function performUpkeep(bytes calldata performData_) external override {
        (
            uint256 currentIndex,
            bool didHarvest,
            uint256 gasOverhead
        ) = abi.decode(performData_, (uint256, bool, uint256));

        _runUpkeep(
            currentIndex,
            didHarvest,
            gasOverhead
        );
    }

    /**
     * @dev This contract must be manager of the vaultRegistry to be able to write to it.
     */
    function _runUpkeep(
        uint256 currentIndex_,
        bool didHarvest_,
        uint256 gasOverhead_
    ) internal {
        // Get all vault addresses.
        address[] memory vaults = _vaultRegistry.allVaultAddresses();

        address vaultAddress = vaults[currentIndex_];

        if (didHarvest_) {
            _vaultRegistry.setHarvestFunctionGasOverhead(vaultAddress, gasOverhead_);
        }
        
        // Update index
        _index = UpkeepLibrary._getCircularIndex(currentIndex_, 1, vaults.length);

        if (_index == 0) {
            /* solhint-disable not-rely-on-time */
            _lastUpdateCycle = block.timestamp;
            /* solhint-enable not-rely-on-time */
        }
    }

    /*     */
    /* Set */
    /*     */

    /**
     * @notice Manually set lastUpdateCycle
     * @param lastUpdateCycle_.
     */
    function setLastUpdateCycle(uint256 lastUpdateCycle_) external onlyManager {
        _lastUpdateCycle = lastUpdateCycle_;
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
