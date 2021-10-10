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

    function checker() external view returns (bool, bytes memory execPayload) {
        function (address) view returns (bool) harvestCondition = _willHarvestStrategy;
        address[] memory vaults = vaultRegistry.allVaultAddresses();
        
        uint256 numberOfStrategiesToHarvest = _countStrategiesToHarvest(vaults, harvestCondition);
        if (numberOfStrategiesToHarvest == 0)
            return (false, bytes("BeefyAutoHarvester: No strats to harvest"));

        address[] memory strategiesToHarvest = _buildStrategiesToHarvest(vaults, harvestCondition, numberOfStrategiesToHarvest);

        execPayload = abi.encodeWithSelector(
            IMultiHarvest.harvest.selector,
            strategiesToHarvest
        );

        return (true, execPayload);
    }

    function _buildStrategiesToHarvest(address[] memory _vaults, function (address) view returns (bool) _harvestCondition, uint256 numberOfStrategiesToHarvest)
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

            if (_harvestCondition(strategy)) {
                strategiesToHarvest[strategyPositionInArray] = address(strategy);
                strategyPositionInArray += 1;
            }

            if (strategyPositionInArray == numberOfStrategiesToHarvest - 1) break;
        }

        return strategiesToHarvest;
    }

    function _countStrategiesToHarvest(address[] memory _vaults, function (address) view returns (bool) _harvestCondition)
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

            if (_harvestCondition(strategyAddress)) numberOfStrategiesToHarvest += 1;
        }

        return numberOfStrategiesToHarvest;
    }

    function _willHarvestStrategy(address _strategy) 
        internal
        view
        returns (bool)
    {
        return _canHarvestStrategy(_strategy) && _shouldHarvestStrategy(_strategy);
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

    function _shouldHarvestStrategy(address _strategy)
        internal
        view
        returns (bool)
    {
        IStrategy strategy = IStrategy(_strategy);

        bool hasBeenHarvestedToday = strategy.lastHarvest() < 1 days;

        uint256 callRewardAmount = strategy.callReward();

        bool isProfitableHarvest = callRewardAmount >= taskTreasury.maxFee();

        bool shouldHarvestStrategy = isProfitableHarvest ||
            (!hasBeenHarvestedToday && callRewardAmount > 0);

        return shouldHarvestStrategy;
    }
}