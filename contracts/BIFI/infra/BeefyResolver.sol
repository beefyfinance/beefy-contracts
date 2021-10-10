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
        function (address) view returns (bool) harvestCondition = _willHarvestStrat;
        
        uint256 numberOfStratsToHarvest;
        address[] memory vaults = vaultRegistry.allVaultAddresses();

        // count the number of strategies to harvest.
        for (uint256 index; index < vaults.length; index++) {
            address vaultAddress = vaults[index];
            IVault vault = IVault(vaultAddress);

            address strategyAddress = vault.strategy();

            if (harvestCondition(strategyAddress)) numberOfStratsToHarvest += 1;
        }

        if (numberOfStratsToHarvest == 0)
            return (false, bytes("BeefyAutoHarvester: No strats to harvest"));

        uint256 strategyPositionInArray;
        address[] memory strategiesToHarvest = new address[](
            numberOfStratsToHarvest
        );


        // create array of strategies to harvest.
        for (uint256 index; index < vaults.length; index++) {
            IVault vault = IVault(vaults[index]);

            address strategy = vault.strategy();

            if (harvestCondition(strategy)) {
                strategiesToHarvest[strategyPositionInArray] = address(strategy);
                strategyPositionInArray += 1;
            }

            if (strategyPositionInArray == numberOfStratsToHarvest - 1) break;
        }

        execPayload = abi.encodeWithSelector(
            IMultiHarvest.harvest.selector,
            strategiesToHarvest
        );

        return (true, execPayload);
    }

    function _willHarvestStrat(address _strategy) 
        internal
        view
        returns (bool)
    {
        return _canHarvestStrat(_strategy) && _shouldHarvestStrat(_strategy);
    }

    function _canHarvestStrat(address _strategy) 
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

    function _shouldHarvestStrat(address _strategy)
        internal
        view
        returns (bool)
    {
        IStrategy strategy = IStrategy(_strategy);

        bool hasBeenHarvestedToday = strategy.lastHarvest() < 1 days;

        uint256 callRewardAmount = strategy.callReward();

        bool isProfitableHarvest = callRewardAmount >= taskTreasury.maxFee();

        bool shouldHarvestStrat = isProfitableHarvest ||
            (!hasBeenHarvestedToday && callRewardAmount > 0);

        return shouldHarvestStrat;
    }
}