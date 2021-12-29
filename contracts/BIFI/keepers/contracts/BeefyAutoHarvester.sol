// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/IPegSwap.sol";
import "../interfaces/IKeeperRegistry.sol";
import "../interfaces/IBeefyVault.sol";
import "../interfaces/IBeefyStrategy.sol";
import "../interfaces/IBeefyRegistry.sol";

/* solhint-disable max-states-count */
contract BeefyAutoHarvester is Initializable, OwnableUpgradeable, KeeperCompatibleInterface {
/* solhint-enable max-states-count */
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct HarvestInfo {
        bool willHarvest;
        uint256 estimatedTxCost;
        uint256 callRewardsAmount;
    }

    // access control
    mapping (address => bool) private isManager;
    mapping (address => bool) private isUpkeeper;

    // contracts, only modifiable via setters
    IBeefyRegistry public vaultRegistry;
    IKeeperRegistry public keeperRegistry;

    // util vars, only modifiable via setters
    address public callFeeRecipient;
    uint256 public gasCap;
    uint256 public gasCapBuffer;
    uint256 public harvestGasLimit;
    uint256 public keeperRegistryGasOverhead;
    uint256 public chainlinkTxFeeMultiplier;
    uint256 public keeperRegistryGasOverheadBufferFactor;

    // state vars that will change across upkeeps
    uint256 public startIndex;

    // swapping to keeper gas token, LINK
    address[] public nativeToLinkRoute;
    uint256 public shouldConvertToLinkThreshold;
    IUniswapRouterETH public unirouter;
    address public oracleLink;
    IPegSwap public pegswap;
    uint256 public upkeepId;

    event HarvestSummary(
        uint256 indexed blockNumber,
        uint256 oldStartIndex,
        uint256 newStartIndex,
        uint256 gasPrice,
        uint256 gasUsedByPerformUpkeep,
        uint256 numberOfSuccessfulHarvests,
        uint256 numberOfFailedHarvests,
        uint256 linkConverted
    );
    event ProfitSummary(
        uint256 estimatedTxCost,
        uint256 estimatedCallRewards,
        uint256 estimatedProfit,
        uint256 calculatedTxCost,
        uint256 calculatedCallRewards,
        uint256 calculatedProfit
    );
    event SuccessfulHarvests(uint256 indexed blockNumber, address[] successfulVaults);
    event FailedHarvests(uint256 indexed blockNumber, address[] failedVaults);
    event ConvertedNativeToLink(uint256 indexed blockNumber, uint256 nativeAmount, uint256 linkAmount);
    event HeuristicFailed(uint256 indexed blockNumber, uint256 heuristicEstimatedTxCost, uint256 nonHeuristicEstimatedTxCost, uint256 estimatedCallRewards);

    modifier onlyManager() {
        require(msg.sender == owner() || isManager[msg.sender], "!manager");
        _;
    }

    modifier onlyUpkeeper() {
        require(isUpkeeper[msg.sender], "!upkeeper");
        _;
    }

    function initialize (
        address _vaultRegistry,
        address _keeperRegistry,
        address _unirouter,
        address[] memory _nativeToLinkRoute,
        address _oracleLink,
        address _pegswap,
        uint256 _gasCap,
        uint256 _gasCapBuffer,
        uint256 _harvestGasLimit,
        uint256 _shouldConvertToLinkThreshold,
        uint256 _keeperRegistryGasOverhead
    ) external initializer {
        __Ownable_init();

        vaultRegistry = IBeefyRegistry(_vaultRegistry);
        keeperRegistry = IKeeperRegistry(_keeperRegistry);
        unirouter = IUniswapRouterETH(_unirouter);
        nativeToLinkRoute = _nativeToLinkRoute;
        oracleLink = _oracleLink;
        pegswap = IPegSwap(_pegswap);
        _approveSpending();

        callFeeRecipient = address(this);
        gasCapBuffer = _gasCapBuffer;
        gasCap = _gasCap;
        harvestGasLimit = _harvestGasLimit;
        shouldConvertToLinkThreshold = _shouldConvertToLinkThreshold;
        ( chainlinkTxFeeMultiplier, , , , , , ) = keeperRegistry.getConfig();
        keeperRegistryGasOverhead = _keeperRegistryGasOverhead;
        keeperRegistryGasOverheadBufferFactor = 1;
    }

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
            uint256 vaultIndexToCheck = _getCircularIndex(startIndex, offset, _vaults.length);
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
            vaultIndexToCheck = _getCircularIndex(startIndex, offset, _vaults.length);
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

        uint256 newStartIndex = _getCircularIndex(vaultIndexToCheck, 1, _vaults.length);

        return (harvestInfo, numberOfVaultsToHarvest, newStartIndex);
    }

    // function used to iterate on an array in a circular way
    function _getCircularIndex(uint256 index, uint256 offset, uint256 bufferLength) private pure returns (uint256) {
        return (index + offset) % bufferLength;
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

    // PERFORM UPKEEP SECTION

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

        // convert native to link if needed
        uint256 linkConverted;
        IERC20Upgradeable native = IERC20Upgradeable(nativeToLinkRoute[0]);
        uint256 nativeBalance = native.balanceOf(address(this));

        if (nativeBalance >= shouldConvertToLinkThreshold && upkeepId > 0) {
            linkConverted = _addHarvestedFundsToUpkeep();
        }

        uint256 gasAfter = gasleft();
        uint256 gasUsedByPerformUpkeep = gasBefore - gasAfter;

        // split these into their own functions to avoid `Stack too deep`
        _reportProfitSummary(gasUsedByPerformUpkeep, nonHeuristicEstimatedTxCost, estimatedCallRewards, calculatedCallRewards);
        _reportHarvestSummary(newStartIndex, gasUsedByPerformUpkeep, numberOfSuccessfulHarvests, numberOfFailedHarvests, linkConverted);
    }

    function _reportHarvestSummary(
        uint256 newStartIndex,
        uint256 gasUsedByPerformUpkeep,
        uint256 numberOfSuccessfulHarvests,
        uint256 numberOfFailedHarvests,
        uint256 linkConverted
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
            numberOfFailedHarvests,
            linkConverted
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

    function setUnirouter(address newUnirouter) external onlyManager {
        unirouter = IUniswapRouterETH(newUnirouter);
    }

    function setUpkeepId(uint256 upkeepId_) external onlyManager {
        upkeepId = upkeepId_;
    }

    function setKeeperRegistryGasOverheadBufferFactor(uint256 newFactor) external onlyManager {
        keeperRegistryGasOverheadBufferFactor = newFactor;
    }

    // LINK conversion functions

    function _addHarvestedFundsToUpkeep() internal returns (uint256) {
        _convertNativeToLinkAndWrap();
        uint256 balance = balanceOfOracleLink();
        keeperRegistry.addFunds(upkeepId, uint96(balance));
        return balance;
    }

    function _convertNativeToLinkAndWrap() internal {
        _convertNativeToLink();
        _wrapAllLinkToOracleVersion();
    }

    /* solhint-disable func-name-mixedcase */
    function NATIVE() public view returns (address link) {
    /* solhint-enable func-name-mixedcase */
        return nativeToLinkRoute[0];
    }

    /* solhint-disable func-name-mixedcase */
    function LINK() public view returns (address link) {
    /* solhint-enable func-name-mixedcase */
        return nativeToLinkRoute[nativeToLinkRoute.length - 1];
    }

    function oracleLINK() public view returns (address link) {
        return oracleLink;
    }

    function balanceOfNative() public view returns (uint256 balance) { 
        return IERC20Upgradeable(NATIVE()).balanceOf(address(this));
    }

    function balanceOfLink() public view returns (uint256 balance) { 
        return IERC20Upgradeable(LINK()).balanceOf(address(this));
    }

    function balanceOfOracleLink() public view returns (uint256 balance) { 
        return IERC20Upgradeable(oracleLINK()).balanceOf(address(this));
    }

    function setShouldConvertToLinkThreshold(uint256 newThreshold) external onlyManager {
        shouldConvertToLinkThreshold = newThreshold;
    }

    function convertNativeToLink() external onlyManager {
        _convertNativeToLink();
    }

    function _convertNativeToLink() internal {
        IERC20Upgradeable native = IERC20Upgradeable(nativeToLinkRoute[0]);
        uint256 nativeBalance = native.balanceOf(address(this));
        
        /* solhint-disable not-rely-on-time */
        uint256[] memory amounts = unirouter.swapExactTokensForTokens(nativeBalance, 0, nativeToLinkRoute, address(this), block.timestamp);
        /* solhint-enable not-rely-on-time */
        emit ConvertedNativeToLink(block.number, nativeBalance, amounts[amounts.length-1]);
    }

    function setNativeToLinkRoute(address[] memory _nativeToLinkRoute) external onlyManager {
        require(_nativeToLinkRoute[0] == NATIVE(), "!NATIVE");
        require(_nativeToLinkRoute[_nativeToLinkRoute.length-1] == LINK(), "!LINK");
        nativeToLinkRoute = _nativeToLinkRoute;
    }

    function nativeToLink() external view returns (address[] memory) {
        return nativeToLinkRoute;
    }

    function withdrawAllLink() external onlyManager {
        uint256 amount = IERC20Upgradeable(LINK()).balanceOf(address(this));
        withdrawLink(amount);
    }

    function withdrawLink(uint256 amount) public onlyManager {
        IERC20Upgradeable(LINK()).safeTransfer(msg.sender, amount);
    }

    function _wrapLinkToOracleVersion(uint256 amount) internal {
        pegswap.swap(amount, LINK(), oracleLINK());
    }

    function _wrapAllLinkToOracleVersion() internal {
        _wrapLinkToOracleVersion(balanceOfLink());
    }

    function managerWrapAllLinkToOracleVersion() external onlyManager {
        _wrapAllLinkToOracleVersion();
    }

    function unwrapToDexLink(uint256 amount) public onlyManager {
        pegswap.swap(amount, oracleLINK(), LINK());
    }

    function unwrapAllToDexLink() public onlyManager {
        unwrapToDexLink(balanceOfOracleLink());
    }

    // approve pegswap spending to swap from erc20 link to oracle compatible link
    function _approveLinkSpending() internal {
        address pegswapAddress = address(pegswap);
        IERC20Upgradeable(LINK()).safeApprove(pegswapAddress, 0);
        IERC20Upgradeable(LINK()).safeApprove(pegswapAddress, type(uint256).max);

        IERC20Upgradeable(oracleLINK()).safeApprove(pegswapAddress, 0);
        IERC20Upgradeable(oracleLINK()).safeApprove(pegswapAddress, type(uint256).max);
    }

    function _approveNativeSpending() internal {
        address unirouterAddress = address(unirouter);
        IERC20Upgradeable(NATIVE()).safeApprove(unirouterAddress, 0);
        IERC20Upgradeable(NATIVE()).safeApprove(unirouterAddress, type(uint256).max);
    }

    function _approveSpending() internal {
        _approveNativeSpending();
        _approveLinkSpending();
    }
}