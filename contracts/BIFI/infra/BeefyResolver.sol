// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategy {
    function lastHarvest() external view returns (uint256);

    function callReward() external view returns (uint256);

    function paused() external view returns (bool);

    function harvest(address callFeeRecipient) external view; // can be view as will only be executed off chain
}

interface IVaultRegistry {
    function allVaultAddresses() external view returns (address[] memory);
}

interface IVault {
    function strategy() external view returns (address);
}

interface ITaskTreasury {
    function maxFee() external view returns (uint256);
}

interface IMultiHarvest {
    function harvest(address[] memory strategies) external;
}

contract BeefyAutoHarvester {
    IVaultRegistry public immutable vaultRegistry;
    ITaskTreasury public immutable taskTreasury;
    IMultiHarvest public immutable multiHarvest;

    address public immutable callFeeRecipient = address(this);

    constructor(
        address _taskTreasury,
        address _vaultRegistry,
        address _multiHarvest
    ) {
        taskTreasury = ITaskTreasury(_taskTreasury);
        vaultRegistry = IVaultRegistry(_vaultRegistry);
        multiHarvest = IMultiHarvest(_multiHarvest);
    }

    function checker(uint256 _harvestGasLimit, uint256 _numberOfVaultsToCheck, uint256 _numberOfVaultsToSkip, bool _checkAllVaults) external view returns (bool, bytes memory execPayload) {
        function (uint256, address) view returns (bool) harvestCondition = _willHarvestStrategy;
        address[] memory vaults = vaultRegistry.allVaultAddresses();
        address [] memory filteredVaults = _filterVaults(vaults, _numberOfVaultsToCheck, _numberOfVaultsToSkip, _checkAllVaults);
        
        uint256 numberOfStrategiesToHarvest = _countStrategiesToHarvest(_harvestGasLimit, filteredVaults, harvestCondition);
        if (numberOfStrategiesToHarvest == 0)
            return (false, bytes("BeefyAutoHarvester: No strats to harvest"));

        address[] memory strategiesToHarvest = _buildStrategiesToHarvest(_harvestGasLimit, filteredVaults, harvestCondition, numberOfStrategiesToHarvest);

        execPayload = abi.encodeWithSelector(
            IMultiHarvest.harvest.selector,
            strategiesToHarvest
        );

        return (true, execPayload);
    }

    function _filterVaults(address[] memory _vaults, uint256 _numberOfVaultsToCheck, uint256 _numberOfVaultsToSkip, bool _checkAllVaults) 
        internal    
        pure    
        returns (address[] memory) 
    {

        uint256 filteredLength = _checkAllVaults
            ? _vaults.length
            : _numberOfVaultsToSkip + _numberOfVaultsToCheck > _vaults.length 
            ? _vaults.length - _numberOfVaultsToSkip
            : _numberOfVaultsToCheck;

        address[] memory filteredVaults = new address[](filteredLength); 

        for (uint256 index; index < filteredLength; index++) {
            uint256 offset = index + _numberOfVaultsToSkip;
            filteredVaults[index] = _vaults[offset];
        }

        return filteredVaults;
    }

    function _buildStrategiesToHarvest(uint256 _harvestGasLimit, address[] memory _vaults, function (uint256, address) view returns (bool) _harvestCondition, uint256 numberOfStrategiesToHarvest)
        internal
        view
        returns (address[] memory)
    {
        uint256 strategyPositionInArray;
        address[] memory strategiesToHarvest = new address[](
            numberOfStrategiesToHarvest
        );

        // create array of strategies to harvest.
        for (uint256 index; index < _vaults.length; index++) {
            IVault vault = IVault(_vaults[index]);

            address strategy = vault.strategy();

            if (_harvestCondition(_harvestGasLimit, strategy)) {
                strategiesToHarvest[strategyPositionInArray] = address(strategy);
                strategyPositionInArray += 1;
            }

            if (strategyPositionInArray == numberOfStrategiesToHarvest - 1) break;
        }

        return strategiesToHarvest;
    }

    function _countStrategiesToHarvest(uint256 _harvestGasLimit, address[] memory _vaults, function (uint256, address) view returns (bool) _harvestCondition)
        internal
        view
        returns (uint256)
    {
        uint256 numberOfStrategiesToHarvest;

        // count the number of strategies to harvest.
        for (uint256 index; index < _vaults.length; index++) {
            address vaultAddress = _vaults[index];
            IVault vault = IVault(vaultAddress);

            address strategyAddress = vault.strategy();

            if (_harvestCondition(_harvestGasLimit, strategyAddress)) numberOfStrategiesToHarvest += 1;
        }

        return numberOfStrategiesToHarvest;
    }

    function _willHarvestStrategy(uint256 _harvestGasLimit, address _strategy) 
        internal
        view
        returns (bool)
    {
        return _canHarvestStrategy(_strategy) && _shouldHarvestStrategy(_harvestGasLimit, _strategy);
    }

    function _canHarvestStrategy(address _strategy) 
        internal
        view
        returns (bool)
    {
        IStrategy strategy = IStrategy(_strategy);

        bool isPaused = strategy.paused();

        bool canHarvest = false;

        if (isPaused) 
        {
            canHarvest = false;
        }
        else 
        {
            try strategy.harvest(callFeeRecipient)
            {
                canHarvest = true;
            }
            catch
            {
                canHarvest = false;
            }
        }

        return canHarvest;
    }

    function _shouldHarvestStrategy(uint256 _harvestGasLimit, address _strategy)
        internal
        view
        returns (bool)
    {
        IStrategy strategy = IStrategy(_strategy);

        bool hasBeenHarvestedToday = strategy.lastHarvest() < 1 days;

        uint256 callRewardAmount = strategy.callReward();

        uint256 txFee = _harvestGasLimit * tx.gasprice;

        bool isProfitableHarvest = callRewardAmount >= txFee;

        bool shouldHarvestStrategy = isProfitableHarvest ||
            (!hasBeenHarvestedToday && callRewardAmount > 0);

        return shouldHarvestStrategy;
    }
}