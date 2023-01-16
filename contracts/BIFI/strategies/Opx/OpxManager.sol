// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

interface IRewardPool {
    function notifyRewardAmount(uint256 amount) external;
    function transferOwnership(address owner) external;
    function reward() external view returns (address);
}

contract OpxManager is OwnableUpgradeable, PausableUpgradeable {
    /**
     * @dev Beefy Contracts:
     * {keeper} - Address to manage a few lower risk features of the strat.
     * {rewardPool} - Address for OPX rewards distribution.
     */
    address public keeper;
    IRewardPool public rewardPool;

    event NewKeeper(address oldKeeper, address newKeeper);
    event NewRewardPool(IRewardPool oldRewardPool, address newRewardPool);

    /**
     * @dev Initializes the manager.
     * @param _keeper address to use as alternative owner.
     * @param _rewardPool address to send rewards to.
     */
   function __OpxManager_init(
        address _keeper,
        address _rewardPool
    ) internal onlyInitializing {
        __Ownable_init();
        __Pausable_init();
        
        keeper = _keeper;
        rewardPool = IRewardPool(_rewardPool);
    }

    /**
     * @dev Checks that caller is either owner or keeper.
     */
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    /**
     * @dev Updates address of the strat keeper.
     * @param _keeper new keeper address.
     */
    function setKeeper(address _keeper) external onlyManager {
        emit NewKeeper(keeper, _keeper);
        keeper = _keeper;
    }

    /**
     * @dev Updates address of the reward pool.
     * @param _newRewardPool new rewardPool address.
     */
    function setRewardPool(address _newRewardPool) external onlyOwner {
        emit NewRewardPool(rewardPool, _newRewardPool);
        rewardPool = IRewardPool(_newRewardPool);
    }

    /**
     * @dev Transfers ownership of the reward pool to a new owner.
     * @param _newOwner new reward pool owner address.
     */
    function transferRewardPoolOwnership(address _newOwner) external onlyOwner {
        rewardPool.transferOwnership(_newOwner);
    }
}
