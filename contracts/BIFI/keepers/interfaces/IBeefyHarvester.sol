// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

interface IBeefyHarvester is KeeperCompatibleInterface {
    struct HarvestInfo {
        bool willHarvest;
        uint256 estimatedTxCost;
        uint256 callRewardsAmount;
    }
        
    event HarvestSummary(
        uint256 indexed blockNumber,
        uint256 oldStartIndex,
        uint256 newStartIndex,
        uint256 gasPrice,
        uint256 gasUsedByPerformUpkeep,
        uint256 numberOfSuccessfulHarvests,
        uint256 numberOfFailedHarvests
    );
    event HeuristicFailed(
        uint256 indexed blockNumber,
        uint256 heuristicEstimatedTxCost,
        uint256 nonHeuristicEstimatedTxCost,
        uint256 estimatedCallRewards
    );
    event ProfitSummary(
        uint256 estimatedTxCost,
        uint256 estimatedCallRewards,
        uint256 estimatedProfit,
        uint256 calculatedTxCost,
        uint256 calculatedCallRewards,
        uint256 calculatedProfit
    );
    event SuccessfulHarvests(
        uint256 indexed blockNumber,
        address[] successfulVaults
    );
    event FailedHarvests(uint256 indexed blockNumber, address[] failedVaults);

    function inCaseTokensGetStuck(address token_) external;

    function initialize(
        address vaultRegistry_,
        address keeperRegistry_,
        address upkeepRefunder_,
        uint256 performUpkeepGasLimit_,
        uint256 performUpkeepGasLimitBuffer_,
        uint256 harvestGasLimit_,
        uint256 keeperRegistryGasOverhead_
    ) external;

    function setHarvestGasConsumption(uint256 harvestGasConsumption_) external;

    function setPerformUpkeepGasLimit(uint256 performUpkeepGasLimit_) external;

    function setPerformUpkeepGasLimitBuffer(
        uint256 performUpkeepGasLimitBuffer_
    ) external;

    function setUpkeepRefunder(address upkeepRefunder_) external;
}
