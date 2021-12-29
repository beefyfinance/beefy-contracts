// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./ManageableUpgradable.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/IPegSwap.sol";
import "../interfaces/IKeeperRegistry.sol";
import "../interfaces/IBeefyVault.sol";
import "../interfaces/IBeefyStrategy.sol";
import "../interfaces/IBeefyRegistry.sol";
import "../interfaces/IBeefyHarvester.sol";
import "../interfaces/IUpkeepRefunder.sol";

import "../libraries/UpkeepHelper.sol";

contract BeefyHarvester is ManageableUpgradable, IBeefyHarvester {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Access control.
    mapping(address => bool) private _isUpkeeper;

    // Contracts.
    IBeefyRegistry public _vaultRegistry;
    IKeeperRegistry public _keeperRegistry;
    IUpkeepRefunder public _upkeepRefunder;

    // Configuration state variables.
    uint256 public _performUpkeepGasLimit;
    uint256 public _performUpkeepGasLimitBuffer;
    uint256 public _harvestGasOverhead; // Estimated average gas cost of calling harvest(). Eventually this needs to live in BeefyRegistry, and needs to be a `per vault` number.
    uint256 public _keeperRegistryGasOverhead; // Gas cost of upstream contract that calls performUpkeep(). This is a private variable on KeeperRegistry.
    uint256 public _chainlinkTxPremiumFactor; // Tx premium factor/multiplier scaled by 1 gwei (10**9).
    address public _callFeeRecipient;

    // State variables that will change across upkeeps.
    uint256 public _startIndex;

    /*             */
    /* Initializer */
    /*             */

    function initialize(
        address vaultRegistry_,
        address keeperRegistry_,
        address upkeepRefunder_,
        uint256 performUpkeepGasLimit_,
        uint256 performUpkeepGasLimitBuffer_,
        uint256 harvestGasLimit_,
        uint256 keeperRegistryGasOverhead_
    ) external initializer {
        __Manageable_init();

        // Set contract references.
        _vaultRegistry = IBeefyRegistry(vaultRegistry_);
        _keeperRegistry = IKeeperRegistry(keeperRegistry_);
        _upkeepRefunder = IUpkeepRefunder(upkeepRefunder_);

        // Initialize state variables from initialize() arguments.
        _performUpkeepGasLimit = performUpkeepGasLimit_;
        _performUpkeepGasLimitBuffer = performUpkeepGasLimitBuffer_;
        _harvestGasOverhead = harvestGasLimit_;
        _keeperRegistryGasOverhead = keeperRegistryGasOverhead_;

        // Initialize state variables derived from initialize() arguments.
        (uint32 paymentPremiumPPB, , , , , , ) = _keeperRegistry.getConfig();
        _chainlinkTxPremiumFactor = uint256(paymentPremiumPPB);
        _callFeeRecipient = address(_upkeepRefunder);
    }

    /*           */
    /* Modifiers */
    /*           */

    modifier onlyUpkeeper() {
        require(_isUpkeeper[msg.sender], "!upkeeper");
        _;
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

        // get vaults to iterate over
        address[] memory vaults = _vaultRegistry.allVaultAddresses();

        // count vaults to harvest that will fit within gas limit
        (
            HarvestInfo[] memory harvestInfo,
            uint256 numberOfVaultsToHarvest,
            uint256 newStartIndex
        ) = _countVaultsToHarvest(vaults);
        if (numberOfVaultsToHarvest == 0) return (false, bytes("BeefyAutoHarvester: No vaults to harvest"));

        (
            address[] memory vaultsToHarvest,
            uint256 heuristicEstimatedTxCost,
            uint256 callRewards
        ) = _buildVaultsToHarvest(vaults, harvestInfo, numberOfVaultsToHarvest);

        uint256 nonHeuristicEstimatedTxCost = _calculateTxCostWithPremium(tx.gasprice, numberOfVaultsToHarvest);

        performData_ = abi.encode(
            vaultsToHarvest,
            newStartIndex,
            heuristicEstimatedTxCost,
            nonHeuristicEstimatedTxCost,
            callRewards
        );

        return (true, performData_);
    }

    function _buildVaultsToHarvest(
        address[] memory vaults_,
        HarvestInfo[] memory willHarvestVault_,
        uint256 numberOfVaultsToHarvest_
    )
        internal
        view
        returns (
            address[] memory vaultsToHarvest_,
            uint256 heuristicEstimatedTxCost_,
            uint256 totalCallRewards_
        )
    {
        uint256 vaultPositionInArray;
        vaultsToHarvest_ = new address[](numberOfVaultsToHarvest_);

        // create array of vaults to harvest. Could reduce code duplication from _countVaultsToHarvest via a another function parameter called _loopPostProcess
        for (uint256 offset; offset < vaults_.length; ++offset) {
            uint256 vaultIndexToCheck = UpkeepHelper._getCircularIndex(_startIndex, offset, vaults_.length);
            address vaultAddress = vaults_[vaultIndexToCheck];

            HarvestInfo memory harvestInfo = willHarvestVault_[offset];

            if (harvestInfo.willHarvest) {
                vaultsToHarvest_[vaultPositionInArray] = vaultAddress;
                heuristicEstimatedTxCost_ += harvestInfo.estimatedTxCost;
                totalCallRewards_ += harvestInfo.callRewardsAmount;
                vaultPositionInArray += 1;
            }

            // no need to keep going if we're past last index
            if (vaultPositionInArray == numberOfVaultsToHarvest_) break;
        }

        return (vaultsToHarvest_, heuristicEstimatedTxCost_, totalCallRewards_);
    }

    function _getAdjustedGasCap() internal view returns (uint256 adjustedPerformUpkeepGasLimit_) {
        return _performUpkeepGasLimit - _performUpkeepGasLimitBuffer;
    }

    function _countVaultsToHarvest(address[] memory vaults_)
        internal
        view
        returns (
            HarvestInfo[] memory harvestInfo_,
            uint256 numberOfVaultsToHarvest_,
            uint256 newStartIndex_
        )
    {
        uint256 gasLeft = _getAdjustedGasCap();
        uint256 vaultIndexToCheck; // hoisted up to be able to set newStartIndex
        harvestInfo_ = new HarvestInfo[](vaults_.length);

        // count the number of vaults to harvest.
        for (uint256 offset; offset < vaults_.length; ++offset) {
            // _startIndex is where to start in the _vaultRegistry array, offset is position from start index (in other words, number of vaults we've checked so far),
            // then modulo to wrap around to the start of the array, until we've checked all vaults, or break early due to hitting gas limit
            // this logic is contained in _getCircularIndex()
            vaultIndexToCheck = UpkeepHelper._getCircularIndex(_startIndex, offset, vaults_.length);
            address vaultAddress = vaults_[vaultIndexToCheck];

            (bool willHarvest, uint256 estimatedTxCost, uint256 callRewardsAmount) = _willHarvestVault(vaultAddress);

            if (willHarvest && gasLeft >= _harvestGasOverhead) {
                gasLeft -= _harvestGasOverhead;
                numberOfVaultsToHarvest_ += 1;
                harvestInfo_[offset] = HarvestInfo(true, estimatedTxCost, callRewardsAmount);
            }

            if (gasLeft < _harvestGasOverhead) {
                break;
            }
        }

        newStartIndex_ = UpkeepHelper._getCircularIndex(vaultIndexToCheck, 1, vaults_.length);

        return (harvestInfo_, numberOfVaultsToHarvest_, newStartIndex_);
    }

    function _willHarvestVault(address vaultAddress_)
        internal
        view
        returns (
            bool willHarvestVault_,
            uint256 estimatedTxCost_,
            uint256 callRewardAmount_
        )
    {
        (bool shouldHarvestVault, uint256 estimatedTxCost, uint256 callRewardAmount) = _shouldHarvestVault(
            vaultAddress_
        );
        bool canHarvestVault = _canHarvestVault(vaultAddress_);

        willHarvestVault_ = canHarvestVault && shouldHarvestVault;

        return (willHarvestVault_, estimatedTxCost, callRewardAmount);
    }

    function _canHarvestVault(address vaultAddress_) internal view returns (bool canHarvest_) {
        IBeefyVault vault = IBeefyVault(vaultAddress_);
        IBeefyStrategy strategy = IBeefyStrategy(vault.strategy());

        bool isPaused = strategy.paused();

        canHarvest_ = !isPaused;

        return canHarvest_;
    }

    function _shouldHarvestVault(address vaultAddress_)
        internal
        view
        returns (
            bool shouldHarvestVault_,
            uint256 txCostWithPremium_,
            uint256 callRewardAmount_
        )
    {
        IBeefyVault vault = IBeefyVault(vaultAddress_);
        IBeefyStrategy strategy = IBeefyStrategy(vault.strategy());

        bool hasBeenHarvestedToday = strategy.lastHarvest() < 1 days;

        uint256 callRewardAmount = strategy.callReward();

        uint256 txCostWithPremium = _buildTxCost() * _chainlinkTxPremiumFactor;
        bool isProfitableHarvest = callRewardAmount >= txCostWithPremium;

        bool shouldHarvestVault = isProfitableHarvest || (!hasBeenHarvestedToday && callRewardAmount > 0);

        return (shouldHarvestVault, txCostWithPremium, callRewardAmount);
    }

    function _estimateAdditionalPremiumFromOverhead() internal view returns (uint256 evenlyDistributedOverheadPerVault_) {
        uint256 estimatedVaultCountPerUpkeep = _getAdjustedGasCap() / _harvestGasOverhead;
        // Evenly distribute the overhead to all vaults, assuming we will harvest max amount of vaults everytime.
        uint256 evenlyDistributedOverheadPerVault = _keeperRegistryGasOverhead / estimatedVaultCountPerUpkeep;
        return evenlyDistributedOverheadPerVault;
    }

    function _buildTxCost() internal view returns (uint256 txCost_) {
        uint256 rawTxCost = tx.gasprice * _harvestGasOverhead;
        return rawTxCost + _estimateAdditionalPremiumFromOverhead();
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
            vaultsToHarvest,
            newStartIndex,
            heuristicEstimatedTxCost,
            nonHeuristicEstimatedTxCost,
            estimatedCallRewards
        );
    }

    function _runUpkeep(
        address[] memory vaults_,
        uint256 newStartIndex_,
        uint256 heuristicEstimatedTxCost_,
        uint256 nonHeuristicEstimatedTxCost_,
        uint256 estimatedCallRewards_
    ) internal {
        // Make sure estimate looks good.
        if (estimatedCallRewards_ < nonHeuristicEstimatedTxCost_) {
            emit HeuristicFailed(
                block.number,
                heuristicEstimatedTxCost_,
                nonHeuristicEstimatedTxCost_,
                estimatedCallRewards_
            );
        }

        uint256 gasBefore = gasleft();
        // multi harvest
        require(vaults_.length > 0, "No vaults to harvest");
        (
            uint256 numberOfSuccessfulHarvests,
            uint256 numberOfFailedHarvests,
            uint256 calculatedCallRewards
        ) = _multiHarvest(vaults_);

        // ensure newStartIndex_ is valid and set _startIndex
        uint256 vaultCount = _vaultRegistry.getVaultCount();
        require(newStartIndex_ >= 0 && newStartIndex_ < vaultCount, "newStartIndex_ out of range.");
        _startIndex = newStartIndex_;

        uint256 gasAfter = gasleft();
        uint256 gasUsedByPerformUpkeep = gasBefore - gasAfter;

        // split these into their own functions to avoid `Stack too deep`
        _reportProfitSummary(
            gasUsedByPerformUpkeep,
            nonHeuristicEstimatedTxCost_,
            estimatedCallRewards_,
            calculatedCallRewards
        );
        _reportHarvestSummary(
            newStartIndex_,
            gasUsedByPerformUpkeep,
            numberOfSuccessfulHarvests,
            numberOfFailedHarvests
        );
    }

    function _reportHarvestSummary(
        uint256 newStartIndex_,
        uint256 gasUsedByPerformUpkeep_,
        uint256 numberOfSuccessfulHarvests_,
        uint256 numberOfFailedHarvests_
    ) internal {
        emit HarvestSummary(
            block.number,
            // state variables
            _startIndex,
            newStartIndex_,
            // gas metrics
            tx.gasprice,
            gasUsedByPerformUpkeep_,
            // summary metrics
            numberOfSuccessfulHarvests_,
            numberOfFailedHarvests_
        );
    }

    function _reportProfitSummary(
        uint256 gasUsedByPerformUpkeep_,
        uint256 nonHeuristicEstimatedTxCost_,
        uint256 estimatedCallRewards_,
        uint256 calculatedCallRewards_
    ) internal {
        uint256 estimatedTxCost = nonHeuristicEstimatedTxCost_; // use nonHeuristic here as its more accurate
        uint256 estimatedProfit = estimatedCallRewards_ - estimatedTxCost;

        uint256 calculatedTxCost = tx.gasprice * (gasUsedByPerformUpkeep_ + _keeperRegistryGasOverhead);
        uint256 calculatedTxCostWithPremium = _calculateTxCostWithPremium(tx.gasprice, calculatedTxCost);
        uint256 calculatedProfit = calculatedCallRewards_ - calculatedTxCostWithPremium;

        emit ProfitSummary(
            // predicted values
            estimatedTxCost,
            estimatedCallRewards_,
            estimatedProfit,
            // calculated values
            calculatedTxCost,
            calculatedCallRewards_,
            calculatedProfit
        );
    }

    function _multiHarvest(address[] memory vaults_)
        internal
        returns (
            uint256 numberOfSuccessfulHarvests_,
            uint256 numberOfFailedHarvests_,
            uint256 calculatedCallRewards_
        )
    {
        bool[] memory isFailedHarvest = new bool[](vaults_.length);
        for (uint256 i = 0; i < vaults_.length; ++i) {
            IBeefyStrategy strategy = IBeefyStrategy(IBeefyVault(vaults_[i]).strategy());
            uint256 toAdd = strategy.callReward();
            bool didHarvest;
            try strategy.harvest(_callFeeRecipient) {
                didHarvest = true;
            } catch {
                // try old function signature
                try strategy.harvestWithCallFeeRecipient(_callFeeRecipient) {
                    didHarvest = true;
                } catch {
                    isFailedHarvest[i] = true;
                }
            }

            // Add rewards to cumulative tracker.
            if (didHarvest) {
                calculatedCallRewards_ += toAdd;
            }
        }

        (address[] memory successfulHarvests, address[] memory failedHarvests) = _getSuccessfulAndFailedVaults(
            vaults_,
            isFailedHarvest
        );

        emit SuccessfulHarvests(block.number, successfulHarvests);
        emit FailedHarvests(block.number, failedHarvests);

        return (successfulHarvests.length, failedHarvests.length, calculatedCallRewards_);
    }

    function _getSuccessfulAndFailedVaults(address[] memory vaults_, bool[] memory isFailedHarvest_)
        internal
        pure
        returns (address[] memory successfulHarvests_, address[] memory failedHarvests_)
    {
        uint256 failedCount;
        for (uint256 i = 0; i < vaults_.length; i++) {
            if (isFailedHarvest_[i]) {
                failedCount += 1;
            }
        }

        successfulHarvests_ = new address[](vaults_.length - failedCount);
        failedHarvests_ = new address[](failedCount);
        uint256 failedHarvestIndex;
        uint256 successfulHarvestsIndex;
        for (uint256 i = 0; i < vaults_.length; i++) {
            if (isFailedHarvest_[i]) {
                failedHarvests_[failedHarvestIndex++] = vaults_[i];
            } else {
                successfulHarvests_[successfulHarvestsIndex++] = vaults_[i];
            }
        }

        return (successfulHarvests_, failedHarvests_);
    }

    /*     */
    /* Set */
    /*     */

    function setUpkeepers(address[] memory upkeepers_, bool status_) external onlyManager {
        for (uint256 upkeeperIndex = 0; upkeeperIndex < upkeepers_.length; upkeeperIndex++) {
            _setUpkeeper(upkeepers_[upkeeperIndex], status_);
        }
    }

    function _setUpkeeper(address upkeeper_, bool status_) internal {
        _isUpkeeper[upkeeper_] = status_;
    }

    function setPerformUpkeepGasLimit(uint256 performUpkeepGasLimit_) external onlyManager {
        _performUpkeepGasLimit = performUpkeepGasLimit_;
    }

    function setPerformUpkeepGasLimitBuffer(uint256 performUpkeepGasLimitBuffer_) external onlyManager {
        _performUpkeepGasLimitBuffer = performUpkeepGasLimitBuffer_;
    }

    function setHarvestGasConsumption(uint256 harvestGasConsumption_) external onlyManager {
        _harvestGasOverhead = harvestGasConsumption_;
    }

    /*      */
    /* View */
    /*      */

    function _estimateUpkeepGasUnits(uint256 numberOfVaultsToHarvest_) internal view returns (uint256) {
        uint256 totalGasUnitsForAllVaults = _harvestGasOverhead * numberOfVaultsToHarvest_;
        uint256 gasUnitsWithOverhead = _keeperRegistryGasOverhead + totalGasUnitsForAllVaults;
        return gasUnitsWithOverhead;
    }

    function _calculateGasCostWithPremium(uint256 numberOfVaultsToHarvest_) internal view returns (uint256) {
        uint256 gasUnits = _estimateUpkeepGasUnits(numberOfVaultsToHarvest_);
        return _calculateTxCostWithPremium(gasUnits);
    }

    function _calculateTxCostWithPremium(uint256 gasprice_, uint256 gasUnits_) internal view returns (uint256) {
        return tx.gasprice * gasUnits_ * _chainlinkTxPremiumFactor;
    }

    /*      */
    /* Misc */
    /*      */

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
