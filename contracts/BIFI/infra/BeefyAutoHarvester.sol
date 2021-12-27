// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

import "../interfaces/common/IUniswapRouterETH.sol";
import "../interfaces/pegswap/IPegSwap.sol";
import "../interfaces/keepers/IKeeperRegistry.sol";

interface IAutoStrategy {
    function lastHarvest() external view returns (uint256);

    function callReward() external view returns (uint256);

    function paused() external view returns (bool);

    function harvest(address callFeeRecipient) external view; // can be view as will only be executed off chain
}

interface IStrategyMultiHarvest {
    function harvest(address callFeeRecipient) external; // used for multiharvest in perform upkeep, this one doesn't have view
    function harvestWithCallFeeRecipient(address callFeeRecipient) external; // back compat call
}

interface IVaultRegistry {
    function allVaultAddresses() external view returns (address[] memory);
    function getVaultCount() external view returns(uint256 count);
}

interface IVault {
    function strategy() external view returns (address);
}

contract BeefyAutoHarvester is Initializable, OwnableUpgradeable, KeeperCompatibleInterface {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // access control
    mapping (address => bool) private isManager;
    mapping (address => bool) private isUpkeeper;

    // contracts, only modifiable via setters
    IVaultRegistry public vaultRegistry;
    IKeeperRegistry public keeperRegistry;

    // util vars, only modifiable via setters
    address public callFeeRecipient;
    uint256 public gasCap;
    uint256 public gasCapBuffer;
    uint256 public harvestGasLimit;
    uint256 public keeperRegistryGasOverhead;
    uint256 public txPremiumFactor;
    uint256 public managerProfitabilityBuffer; // extra factor on top of tx premium call rewards must clear to trigger a harvest

    // state vars that will change across upkeeps
    uint256 public startIndex;

    // swapping to keeper gas token, LINK
    address[] public nativeToLinkRoute;
    uint256 public shouldConvertToLinkThreshold;
    IUniswapRouterETH public unirouter;
    address public oracleLink;
    IPegSwap public pegswap;
    uint256 public upkeepId;

    event SuccessfulHarvests(address[] successfulVaults);
    event FailedHarvests(address[] failedVaults);
    event ConvertedNativeToLink(uint256 nativeAmount, uint256 linkAmount);

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
        uint256 _keeperRegistryGasOverhead,
        uint256 _managerProfitabilityBuffer
    ) external initializer {
        __Ownable_init();

        vaultRegistry = IVaultRegistry(_vaultRegistry);
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
        ( txPremiumFactor, , , , , , ) = keeperRegistry.getConfig();
        keeperRegistryGasOverhead = _keeperRegistryGasOverhead;
        managerProfitabilityBuffer = _managerProfitabilityBuffer;
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

        // save harvest condition in variable as it will be reused in count and build
        function (address) view returns (bool) harvestCondition = _willHarvestVault;
        // get vaults to iterate over
        address[] memory vaults = vaultRegistry.allVaultAddresses();
        
        // count vaults to harvest that will fit within gas limit
        (bool[] memory willHarvestVault, uint256 numberOfVaultsToHarvest, uint256 newStartIndex) = _countVaultsToHarvest(vaults, harvestCondition);
        if (numberOfVaultsToHarvest == 0)
            return (false, bytes("BeefyAutoHarvester: No vaults to harvest"));

        address[] memory vaultsToHarvest = _buildVaultsToHarvest(vaults, willHarvestVault, numberOfVaultsToHarvest);

        performData = abi.encode(
            vaultsToHarvest,
            newStartIndex
        );

        return (true, performData);
    }

    function _buildVaultsToHarvest(address[] memory _vaults, bool[] memory willHarvestVault, uint256 numberOfVaultsToHarvest)
        internal
        view
        returns (address[] memory)
    {
        uint256 vaultPositionInArray;
        address[] memory vaultsToHarvest = new address[](
            numberOfVaultsToHarvest
        );

        // create array of vaults to harvest. Could reduce code duplication from _countVaultsToHarvest via a another function parameter called _loopPostProcess
        for (uint256 offset; offset < _vaults.length; ++offset) {
            uint256 vaultIndexToCheck = _getCircularIndex(startIndex, offset, _vaults.length);
            address vaultAddress = _vaults[vaultIndexToCheck];

            bool willHarvest = willHarvestVault[offset];

            if (willHarvest) {
                vaultsToHarvest[vaultPositionInArray] = vaultAddress;
                vaultPositionInArray += 1;
            }

            // no need to keep going if we're past last index
            if (vaultPositionInArray == numberOfVaultsToHarvest) break;
        }

        return vaultsToHarvest;
    }

    function _getAdjustedGasCap() internal view returns (uint256) {
        return gasCap - gasCapBuffer;
    }

    function _countVaultsToHarvest(address[] memory _vaults, function (address) view returns (bool) _harvestCondition)
        internal
        view
        returns (bool[] memory, uint256, uint256)
    {
        uint256 gasLeft = _getAdjustedGasCap();
        uint256 vaultIndexToCheck; // hoisted up to be able to set newStartIndex
        uint256 numberOfVaultsToHarvest; // used to create fixed size array in _buildVaultsToHarvest
        bool[] memory willHarvestVault = new bool[](_vaults.length);

        // count the number of vaults to harvest.
        for (uint256 offset; offset < _vaults.length; ++offset) {
            // startIndex is where to start in the vaultRegistry array, offset is position from start index (in other words, number of vaults we've checked so far), 
            // then modulo to wrap around to the start of the array, until we've checked all vaults, or break early due to hitting gas limit
            // this logic is contained in _getCircularIndex()
            vaultIndexToCheck = _getCircularIndex(startIndex, offset, _vaults.length);
            address vaultAddress = _vaults[vaultIndexToCheck];

            bool willHarvest = _harvestCondition(vaultAddress);

            if (willHarvest && gasLeft >= harvestGasLimit) {
                gasLeft -= harvestGasLimit;
                numberOfVaultsToHarvest += 1;
                willHarvestVault[offset] = true;
            }

            if (gasLeft < harvestGasLimit) {
                break;
            }
        }

        uint256 newStartIndex = _getCircularIndex(vaultIndexToCheck, 1, _vaults.length);

        return (willHarvestVault, numberOfVaultsToHarvest, newStartIndex);
    }

    // function used to iterate on an array in a circular way
    function _getCircularIndex(uint256 index, uint256 offset, uint256 bufferLength) private pure returns (uint256) {
        return (index + offset) % bufferLength;
    }

    function _willHarvestVault(address _vaultAddress) 
        internal
        view
        returns (bool)
    {
        bool shouldHarvestVault = _shouldHarvestVault(_vaultAddress);
        bool canHarvestVault = _canHarvestVault(_vaultAddress);
        
        bool willHarvestVault = canHarvestVault && shouldHarvestVault;
        
        return willHarvestVault;
    }

    function _canHarvestVault(address _vaultAddress) 
        internal
        view
        returns (bool)
    {
        IVault vault = IVault(_vaultAddress);
        IAutoStrategy strategy = IAutoStrategy(vault.strategy());

        bool isPaused = strategy.paused();

        bool canHarvest = !isPaused;

        return canHarvest;
    }

    function _shouldHarvestVault(address _vaultAddress)
        internal
        view
        returns (bool)
    {
        IVault vault = IVault(_vaultAddress);
        IAutoStrategy strategy = IAutoStrategy(vault.strategy());

        bool hasBeenHarvestedToday = strategy.lastHarvest() < 1 days;

        uint256 callRewardAmount = strategy.callReward();

        bool isProfitableHarvest = _isProfitable(callRewardAmount);

        bool shouldHarvest = isProfitableHarvest ||
            (!hasBeenHarvestedToday && callRewardAmount > 0);

        return shouldHarvest;
    }

    function _estimateAdditionalPremiumFactorFromOverhead() internal view returns (uint256) {
        uint256 estimatedMaxVaultsPerUpkeep = _getAdjustedGasCap() / harvestGasLimit;
        // Evenly distribute the overhead to all vaults, assuming we will harvest max amount of vaults everytime.
        uint256 evenlyDistributedOverheadPerVault = keeperRegistryGasOverhead / estimatedMaxVaultsPerUpkeep;
        // Being additionally conservative by assuming half the max amount of vaults will be harvested, making the overhead to clear higher.
        uint256 adjustedOverheadPerVault = evenlyDistributedOverheadPerVault * 2;

        return adjustedOverheadPerVault;
    }

    function _isProfitable(
        uint256 callRewardAmount
    ) internal view returns (bool) {
        uint256 txCostWithPremium = _buildTxCost() * _buildCostFactor();
        return callRewardAmount >= txCostWithPremium;
    }
    
    function _buildTxCost() internal view returns (uint256) {
        uint256 rawTxCost = tx.gasprice * harvestGasLimit;
        return rawTxCost + _estimateAdditionalPremiumFactorFromOverhead();
    }

    function _buildCostFactor() internal view returns (uint256) {
        uint256 ONE = 10 ** 8;
        return ONE + txPremiumFactor + managerProfitabilityBuffer;
    }

    // PERFORM UPKEEP SECTION

    function performUpkeep(
        bytes calldata performData
    ) external override onlyUpkeeper {
        (
            address[] memory vaults,
            uint256 newStartIndex
        ) = abi.decode(
            performData,
            (address[], uint256)
        );

        _runUpkeep(vaults, newStartIndex);
    }

    function _runUpkeep(address[] memory vaults, uint256 newStartIndex) internal {
        // multi harvest
        require(vaults.length > 0, "No vaults to harvest");
        _multiHarvest(vaults);

        // ensure newStartIndex is valid and set startIndex
        uint256 vaultCount = vaultRegistry.getVaultCount();
        require(newStartIndex >= 0 && newStartIndex < vaultCount, "newStartIndex out of range.");
        startIndex = newStartIndex;

        // convert native to link if needed
        IERC20Upgradeable native = IERC20Upgradeable(nativeToLinkRoute[0]);
        uint256 nativeBalance = native.balanceOf(address(this));

        if (nativeBalance >= shouldConvertToLinkThreshold && upkeepId > 0) {
            _addHarvestedFundsToUpkeep();
        }
    }

    function _multiHarvest(address[] memory vaults) internal {
        bool[] memory isFailedHarvest = new bool[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            IStrategyMultiHarvest strategy = IStrategyMultiHarvest(IVault(vaults[i]).strategy());
            try strategy.harvest(callFeeRecipient) {
            } catch {
                // try old function signature
                try strategy.harvestWithCallFeeRecipient(callFeeRecipient) {
                }
                catch {
                    isFailedHarvest[i] = true;
                }
            }
        }

        (address[] memory successfulHarvests, address[] memory failedHarvests) = _getSuccessfulAndFailedVaults(vaults, isFailedHarvest);
        
        emit SuccessfulHarvests(successfulHarvests);
        emit FailedHarvests(failedHarvests);
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

    function setManagerProfitabilityBuffer(uint256 newManagerProfitabilityBuffer) external onlyManager {
        managerProfitabilityBuffer = newManagerProfitabilityBuffer;
    }

    function setUpkeepId(uint256 upkeepId_) external onlyManager {
        upkeepId = upkeepId_;
    }

    // LINK conversion functions

    function _addHarvestedFundsToUpkeep() internal {
        _convertNativeToLinkAndWrap();
        keeperRegistry.addFunds(upkeepId, uint96(balanceOfOracleLink()));
    }

    function _convertNativeToLinkAndWrap() internal {
        _convertNativeToLink();
        _wrapAllLinkToOracleVersion();
    }

    function NATIVE() public view returns (address link) {
        return nativeToLinkRoute[0];
    }

    function LINK() public view returns (address link) {
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
        uint256[] memory amounts = unirouter.swapExactTokensForTokens(nativeBalance, 0, nativeToLinkRoute, address(this), block.timestamp);
        emit ConvertedNativeToLink(nativeBalance, amounts[amounts.length-1]);
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