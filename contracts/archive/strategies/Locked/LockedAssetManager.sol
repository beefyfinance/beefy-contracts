// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/utils/math/SafeMath.sol";

contract LockedAssetManager is  Ownable, Pausable {
    using SafeERC20 for IERC20;

    /**
     * @dev Beefy Contracts:
     * {keeper} - Address to manage a few lower risk features of the strat.
     * {rewardPool} - Address for distributing locked want rewards.
     */

    address public keeper;
    address public rewardPool;



    /**
     * @dev Initializes the base strategy.
     * @param _keeper address to use as alternative owner.
     * @param _rewardPool address of reward pool.
     */
    constructor(
        address _keeper,
        address _rewardPool
    ) {
        keeper = _keeper;
        rewardPool = _rewardPool;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // checks that caller is the reward pool.
    modifier onlyRewardPool() {
        require(msg.sender == rewardPool, "!rewardPool");
        _;
    }

    /**
     * @dev Updates address of the strat keeper.
     * @param _keeper new keeper address.
     */
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
    }

    /**
     * @dev Updates address where reward pool where want is rewarded.
     * @param _rewardPool new reward pool address.
     */
    function setRewardPool(address _rewardPool) external onlyOwner {
        rewardPool = _rewardPool;
    }
}
