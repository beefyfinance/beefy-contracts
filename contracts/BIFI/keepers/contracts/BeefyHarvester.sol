// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/IPegSwap.sol";
import "../interfaces/IKeeperRegistry.sol";
import "../interfaces/IBeefyVault.sol";
import "../interfaces/IBeefyStrategy.sol";
import "../interfaces/IBeefyRegistry.sol";
import "../interfaces/IBeefyHarvester.sol";
import "../interfaces/IUpkeepRefunder.sol";

import "../libraries/UpkeepHelper.sol";

contract BeefyHarvester is Initializable, OwnableUpgradeable, IBeefyHarvester {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // access control
    mapping (address => bool) private isManager;
    mapping (address => bool) private isUpkeeper;

    // contracts
    IBeefyRegistry public vaultRegistry;
    IKeeperRegistry public keeperRegistry;
    IUpkeepRefunder public upkeepRefunder;
    IERC20Upgradeable public native;

    // util vars
    address public callFeeRecipient;
    uint256 public gasCap;
    uint256 public gasCapBuffer;
    uint256 public harvestGasLimit;
    uint256 public keeperRegistryGasOverhead;
    uint256 public chainlinkTxFeeMultiplier;
    uint256 public keeperRegistryGasOverheadBufferFactor;

    // state vars that will change across upkeeps
    uint256 public startIndex;

    modifier onlyManager() {
        require(msg.sender == owner() || isManager[msg.sender], "!manager");
        _;
    }

    modifier onlyUpkeeper() {
        require(isUpkeeper[msg.sender], "!upkeeper");
        _;
    }

    function initialize (
        address native_,
        address vaultRegistry_,
        address keeperRegistry_,
        uint256 gasCap_,
        uint256 gasCapBuffer_,
        uint256 harvestGasLimit_,
        uint256 keeperRegistryGasOverhead_,
        address upkeepRefunder_
    ) external initializer {
        __Ownable_init();

        native = IERC20Upgradeable(native_);
        vaultRegistry = IBeefyRegistry(vaultRegistry_);
        keeperRegistry = IKeeperRegistry(keeperRegistry_);

        callFeeRecipient = address(this);
        gasCapBuffer = gasCapBuffer_;
        gasCap = gasCap_;
        harvestGasLimit = harvestGasLimit_;
        ( chainlinkTxFeeMultiplier, , , , , , ) = keeperRegistry.getConfig();
        keeperRegistryGasOverhead = keeperRegistryGasOverhead_;
        keeperRegistryGasOverheadBufferFactor = 1;
        upkeepRefunder = IUpkeepRefunder(upkeepRefunder_);
    }

    /*             */
    /* checkUpkeep */
    /*             */

    function checkUpkeep(
        bytes calldata checkData // unused
    )
    external view override
    returns (
      bool upkeepNeeded,
      bytes memory performData // array of vaults + 
    ) {
        checkData; // dummy reference to get rid of unused parameter warning 

        // get vaults to iterate over
        address[] memory vaults = vaultRegistry.allVaultAddresses();
        
        // count vaults to harvest that will fit within gas limit
        (HarvestInfo[] memory harvestInfo, uint256 numberOfVaultsToHarvest, uint256 newStartIndex) = _countVaultsToHarvest(vaults);
        if (numberOfVaultsToHarvest == 0)
            return (false, bytes("BeefyAutoHarvester: No vaults to harvest"));

        ( 
            address[] memory vaultsToHarvest,
            uint256 heuristicEstimatedTxCost,
            uint256 callRewards
        ) = _buildVaultsToHarvest(vaults, harvestInfo, numberOfVaultsToHarvest);

        uint256 nonHeuristicEstimatedTxCost = _estimateUpkeepTxCost(numberOfVaultsToHarvest);

        performData = abi.encode(
            vaultsToHarvest,
            newStartIndex,
            heuristicEstimatedTxCost,
            nonHeuristicEstimatedTxCost,
            callRewards
        );

        return (true, performData);
    }

    function _estimateUpkeepGasUnits(uint256 numberOfVaultsToHarvest) internal view returns (uint256) {
        uint256 totalGasUnitsForAllVaults = harvestGasLimit * numberOfVaultsToHarvest;
        uint256 gasUnitsWithOverhead = keeperRegistryGasOverhead + totalGasUnitsForAllVaults;
        return gasUnitsWithOverhead;
    }

    function _calculateGasCostWithPremium(uint256 numberOfVaultsToHarvest) internal view returns (uint256) {
        uint256 gasUnits = _estimateUpkeepGasUnits(numberOfVaultsToHarvest);
        return _estimateUpkeepTxCost(gasUnits);
    }

    function _estimateUpkeepTxCost(uint256 gasUnits) internal view returns (uint256) {
        return tx.gasprice * gasUnits * _buildChainlinkTxFeeMultiplier();
    }

    function _buildVaultsToHarvest(address[] memory _vaults, HarvestInfo[] memory willHarvestVault, uint256 numberOfVaultsToHarvest)
        internal
        view
        returns (address[] memory, uint256, uint256)
    {
        uint256 vaultPositionInArray;
        address[] memory vaultsToHarvest = new address[](
            numberOfVaultsToHarvest
        );
        uint256 heuristicEstimatedTxCost;
        uint256 totalCallRewards;

        // create array of vaults to harvest. Could reduce code duplication from _countVaultsToHarvest via a another function parameter called _loopPostProcess
        for (uint256 offset; offset < _vaults.length; ++offset) {
            uint256 vaultIndexToCheck = UpkeepHelper._getCircularIndex(startIndex, offset, _vaults.length);
            address vaultAddress = _vaults[vaultIndexToCheck];

            HarvestInfo memory harvestInfo = willHarvestVault[offset];

            if (harvestInfo.willHarvest) {
                vaultsToHarvest[vaultPositionInArray] = vaultAddress;
                heuristicEstimatedTxCost += harvestInfo.estimatedTxCost;
                totalCallRewards += harvestInfo.callRewardsAmount;
                vaultPositionInArray += 1;
            }

            // no need to keep going if we're past last index
            if (vaultPositionInArray == numberOfVaultsToHarvest) break;
        }

        return ( vaultsToHarvest, heuristicEstimatedTxCost, totalCallRewards );
    }

    function _getAdjustedGasCap() internal view returns (uint256) {
        return gasCap - gasCapBuffer;
    }

    function _countVaultsToHarvest(address[] memory _vaults)
        internal
        view
        returns (
            HarvestInfo[] memory,
            uint256,
            uint256
        )
    {
        uint256 gasLeft = _getAdjustedGasCap();
        uint256 vaultIndexToCheck; // hoisted up to be able to set newStartIndex
        uint256 numberOfVaultsToHarvest; // used to create fixed size array in _buildVaultsToHarvest
        HarvestInfo[] memory harvestInfo = new HarvestInfo[](_vaults.length);

        // count the number of vaults to harvest.
        for (uint256 offset; offset < _vaults.length; ++offset) {
            // startIndex is where to start in the vaultRegistry array, offset is position from start index (in other words, number of vaults we've checked so far), 
            // then modulo to wrap around to the start of the array, until we've checked all vaults, or break early due to hitting gas limit
            // this logic is contained in _getCircularIndex()
            vaultIndexToCheck = UpkeepHelper._getCircularIndex(startIndex, offset, _vaults.length);
            address vaultAddress = _vaults[vaultIndexToCheck];

            (
                bool willHarvest,
                uint256 estimatedTxCost,
                uint256 callRewardsAmount
            ) = _willHarvestVault(vaultAddress);

            if (willHarvest && gasLeft >= harvestGasLimit) {
                gasLeft -= harvestGasLimit;
                numberOfVaultsToHarvest += 1;
                harvestInfo[offset] = HarvestInfo(
                    true,
                    estimatedTxCost,
                    callRewardsAmount
                );
            }

            if (gasLeft < harvestGasLimit) {
                break;
            }
        }

        uint256 newStartIndex = UpkeepHelper._getCircularIndex(vaultIndexToCheck, 1, _vaults.length);

        return (harvestInfo, numberOfVaultsToHarvest, newStartIndex);
    }

    function _willHarvestVault(address _vaultAddress) 
        internal
        view
        returns (bool, uint256, uint256)
    {
        (
            bool shouldHarvestVault,
            uint256 estimatedTxCost,
            uint256 callRewardAmount
        ) = _shouldHarvestVault(_vaultAddress);
        bool canHarvestVault = _canHarvestVault(_vaultAddress);
        
        bool willHarvestVault = canHarvestVault && shouldHarvestVault;
        
        return (willHarvestVault, estimatedTxCost, callRewardAmount);
    }

    function _canHarvestVault(address _vaultAddress) 
        internal
        view
        returns (bool)
    {
        IBeefyVault vault = IBeefyVault(_vaultAddress);
        IBeefyStrategy strategy = IBeefyStrategy(vault.strategy());

        bool isPaused = strategy.paused();

        bool canHarvest = !isPaused;

        return canHarvest;
    }

    function _shouldHarvestVault(address _vaultAddress)
        internal
        view
        returns (bool, uint256, uint256)
    {
        IBeefyVault vault = IBeefyVault(_vaultAddress);
        IBeefyStrategy strategy = IBeefyStrategy(vault.strategy());

        bool hasBeenHarvestedToday = strategy.lastHarvest() < 1 days;

        uint256 callRewardAmount = strategy.callReward();

        uint256 txCostWithPremium = _buildTxCost() * _buildChainlinkTxFeeMultiplier();
        bool isProfitableHarvest = callRewardAmount >= txCostWithPremium;

        bool shouldHarvestVault = isProfitableHarvest ||
            (!hasBeenHarvestedToday && callRewardAmount > 0);

        return (shouldHarvestVault, txCostWithPremium, callRewardAmount);
    }

    function _estimateAdditionalPremiumFromOverhead() internal view returns (uint256) {
        uint256 estimatedVaultCountPerUpkeep = _getAdjustedGasCap() / harvestGasLimit;
        // Evenly distribute the overhead to all vaults, assuming we will harvest max amount of vaults everytime.
        uint256 evenlyDistributedOverheadPerVault = keeperRegistryGasOverhead / estimatedVaultCountPerUpkeep;
        return evenlyDistributedOverheadPerVault;
    }

    function _buildTxCost() internal view returns (uint256) {
        uint256 rawTxCost = tx.gasprice * harvestGasLimit;
        return rawTxCost + _estimateAdditionalPremiumFromOverhead();
    }

    function _buildChainlinkTxFeeMultiplier() internal view returns (uint256) {
        uint256 one = 10 ** 8;
        return one + chainlinkTxFeeMultiplier;
    }

    /*               */
    /* performUpkeep */
    /*               */

    function performUpkeep(
        bytes calldata performData
    ) external override onlyUpkeeper {
        (
            address[] memory vaultsToHarvest,
            uint256 newStartIndex,
            uint256 heuristicEstimatedTxCost,
            uint256 nonHeuristicEstimatedTxCost,
            uint256 estimatedCallRewards
        ) = abi.decode(
            performData,
            (
                address[],
                uint256,
                uint256,
                uint256,
                uint256
            )
        );

        _runUpkeep(vaultsToHarvest, newStartIndex, heuristicEstimatedTxCost, nonHeuristicEstimatedTxCost, estimatedCallRewards);
    }

    function _runUpkeep(
        address[] memory vaults,
        uint256 newStartIndex,
        uint256 heuristicEstimatedTxCost,
        uint256 nonHeuristicEstimatedTxCost,
        uint256 estimatedCallRewards
    ) internal {
        // Make sure estimate looks good.
        if (estimatedCallRewards < nonHeuristicEstimatedTxCost) {
            emit HeuristicFailed(block.number, heuristicEstimatedTxCost, nonHeuristicEstimatedTxCost, estimatedCallRewards);
        }

        uint256 gasBefore = gasleft();
        // multi harvest
        require(vaults.length > 0, "No vaults to harvest");
        (
            uint256 numberOfSuccessfulHarvests,
            uint256 numberOfFailedHarvests,
            uint256 calculatedCallRewards
        ) = _multiHarvest(vaults);

        // ensure newStartIndex is valid and set startIndex
        uint256 vaultCount = vaultRegistry.getVaultCount();
        require(newStartIndex >= 0 && newStartIndex < vaultCount, "newStartIndex out of range.");
        startIndex = newStartIndex;

        upkeepRefunder.refundUpkeep(native.balanceOf(address(this)));

        uint256 gasAfter = gasleft();
        uint256 gasUsedByPerformUpkeep = gasBefore - gasAfter;

        // split these into their own functions to avoid `Stack too deep`
        _reportProfitSummary(gasUsedByPerformUpkeep, nonHeuristicEstimatedTxCost, estimatedCallRewards, calculatedCallRewards);
        _reportHarvestSummary(newStartIndex, gasUsedByPerformUpkeep, numberOfSuccessfulHarvests, numberOfFailedHarvests);
    }

    function _reportHarvestSummary(
        uint256 newStartIndex,
        uint256 gasUsedByPerformUpkeep,
        uint256 numberOfSuccessfulHarvests,
        uint256 numberOfFailedHarvests
    ) internal {
        emit HarvestSummary(
            block.number,
            // state variables
            startIndex,
            newStartIndex,
            // gas metrics
            tx.gasprice,
            gasUsedByPerformUpkeep,
            // summary metrics
            numberOfSuccessfulHarvests,
            numberOfFailedHarvests
        );
    }

    function _reportProfitSummary(
        uint256 gasUsedByPerformUpkeep,
        uint256 nonHeuristicEstimatedTxCost,
        uint256 estimatedCallRewards,
        uint256 calculatedCallRewards
    ) internal {
        uint256 estimatedTxCost = nonHeuristicEstimatedTxCost; // use nonHeuristic here as its more accurate
        uint256 estimatedProfit = estimatedCallRewards - estimatedTxCost;

        uint256 calculatedTxCost = tx.gasprice * (gasUsedByPerformUpkeep + keeperRegistryGasOverhead);
        uint256 calculatedTxCostWithPremium = _estimateUpkeepTxCost(calculatedTxCost);
        uint256 calculatedProfit = calculatedCallRewards - calculatedTxCostWithPremium;

        emit ProfitSummary(
            // predicted values
            estimatedTxCost,
            estimatedCallRewards,
            estimatedProfit,
            // calculated values
            calculatedTxCost,
            calculatedCallRewards,
            calculatedProfit
        );
    }

    function _multiHarvest(address[] memory vaults) 
    internal returns (
        uint256,
        uint256,
        uint256
    ) {
        uint256 calculatedCallRewards;
        bool[] memory isFailedHarvest = new bool[](vaults.length);
        for (uint256 i = 0; i < vaults.length; ++i) {
            IBeefyStrategy strategy = IBeefyStrategy(IBeefyVault(vaults[i]).strategy());
            uint256 toAdd = strategy.callReward();
            bool didHarvest;
            try strategy.harvest(callFeeRecipient) {
                didHarvest = true;
            } catch {
                // try old function signature
                try strategy.harvestWithCallFeeRecipient(callFeeRecipient) {
                    didHarvest = true;
                }
                catch {
                    isFailedHarvest[i] = true;
                }
            }

            // Add rewards to cumulative tracker.
            if (didHarvest) {
                calculatedCallRewards += toAdd;
            }
        }

        (address[] memory successfulHarvests, address[] memory failedHarvests) = _getSuccessfulAndFailedVaults(vaults, isFailedHarvest);
        
        emit SuccessfulHarvests(block.number, successfulHarvests);
        emit FailedHarvests(block.number,  failedHarvests);

        return (successfulHarvests.length, failedHarvests.length, calculatedCallRewards);
    }

    function _getSuccessfulAndFailedVaults(address[] memory vaults, bool[] memory isFailedHarvest) internal pure returns (address[] memory successfulHarvests, address[] memory failedHarvests) {
        uint256 failedCount;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (isFailedHarvest[i]) {
                failedCount += 1;
            }
        }

        successfulHarvests = new address[](vaults.length - failedCount);
        failedHarvests = new address[](failedCount);
        uint256 failedHarvestIndex;
        uint256 successfulHarvestsIndex;
        for (uint256 i = 0; i < vaults.length; i++) {
            if (isFailedHarvest[i]) {
                failedHarvests[failedHarvestIndex++] = vaults[i];
            }
            else {
                successfulHarvests[successfulHarvestsIndex++] = vaults[i];
            }
        }

        return (successfulHarvests, failedHarvests);
    }

    // Access control functions

    function setManagers(address[] memory _managers, bool _status) external onlyManager {
        for (uint256 managerIndex = 0; managerIndex < _managers.length; managerIndex++) {
            _setManager(_managers[managerIndex], _status);
        }
    }

    function _setManager(address _manager, bool _status) internal {
        isManager[_manager] = _status;
    }

    function setUpkeepers(address[] memory _upkeepers, bool _status) external onlyManager {
        for (uint256 upkeeperIndex = 0; upkeeperIndex < _upkeepers.length; upkeeperIndex++) {
            _setUpkeeper(_upkeepers[upkeeperIndex], _status);
        }
    }

    function _setUpkeeper(address _upkeeper, bool _status) internal {
        isUpkeeper[_upkeeper] = _status;
    }

    // Set config functions

    function setGasCap(uint256 newGasCap) external onlyManager {
        gasCap = newGasCap;
    }

    function setGasCapBuffer(uint256 newGasCapBuffer) external onlyManager {
        gasCapBuffer = newGasCapBuffer;
    }

    function setHarvestGasLimit(uint256 newHarvestGasLimit) external onlyManager {
        harvestGasLimit = newHarvestGasLimit;
    }

    function setKeeperRegistryGasOverheadBufferFactor(uint256 newFactor) external onlyManager {
        keeperRegistryGasOverheadBufferFactor = newFactor;
    }

    /*      */
    /* View */
    /*      */

}