// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStrategy {
    function lastHarvest() external view returns (uint256);

    function callReward() external view returns (uint256);

    function paused() external view returns (bool);
    
    function harvest(address callFeeRecipient) external;
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
        address[] memory vaults = vaultRegistry.allVaultAddresses();

        uint256 nrOfStratsToHarvest;

        // count number of strategies to harvest.
        for (uint256 x; x < vaults.length; x++) {
            IVault vault = IVault(vaults[x]);

            address strategy = vault.strategy();

            if (_shouldHarvestStrat(strategy)) nrOfStratsToHarvest += 1;
        }

        if (nrOfStratsToHarvest == 0)
            return (false, bytes("BeefyAutoHarvester: No strats to harvest"));

        uint256 pos;
        address[] memory strategiesToHarvest = new address[](
            nrOfStratsToHarvest
        );

        // create array of strategies to harvest.
        for (uint256 x; x < vaults.length; x++) {
            IVault vault = IVault(vaults[x]);

            address strategy = vault.strategy();

            if (_shouldHarvestStrat(strategy)) {
                strategiesToHarvest[pos] = address(strategy);
                pos += 1;
            }

            if (pos == nrOfStratsToHarvest - 1) break;
        }

        execPayload = abi.encodeWithSelector(
            IMultiHarvest.harvest.selector,
            strategiesToHarvest
        );

        return (true, execPayload);
    }

    function _shouldHarvestStrat(address _strategy)
        internal
        view
        returns (bool)
    {
        IStrategy strategy = IStrategy(_strategy);

        uint256 callRewardAmount = strategy.callReward();

        bool hasBeenHarvestedToday = strategy.lastHarvest() < 1 days;

        bool isProfitableHarvest = callRewardAmount >= taskTreasury.maxFee();

        bool shouldHarvestStrat = isProfitableHarvest ||
            (!hasBeenHarvestedToday && callRewardAmount > 0);

        return shouldHarvestStrat;
    }
}