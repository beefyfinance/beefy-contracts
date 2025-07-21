// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRewardPool {
    function notifyRewardAmount(uint256 amount) external;
    function transferOwnership(address owner) external;
}

interface IDelegateManager {
    function setDelegate(bytes32 _id, address _voter) external;
    function clearDelegate(bytes32 _id) external;
    function delegation(address _voteHolder, bytes32 _id) external view returns (address);
}

contract QiManager is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /**
     * @dev Beefy Contracts:
     * {keeper} - Address to manage a few lower risk features of the strat.
     * {rewardPool} - Address for QI rewards distribution.
     */
    address public keeper;
    IRewardPool public rewardPool;
    IDelegateManager public delegateManager = IDelegateManager(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);
    bytes32 public id = bytes32("qidao.eth");

    event NewKeeper(address oldKeeper, address newKeeper);
    event NewRewardPool(IRewardPool oldRewardPool, address newRewardPool);
    event NewVoter(address newVoter);
    event NewVoterParams(IDelegateManager newDelegatManager, bytes32 newId);

    /**
     * @dev Initializes the base strategy.
     * @param _keeper address to use as alternative owner.
     */
   constructor(
        address _keeper,
        address _rewardPool
    ) {

        keeper = _keeper;
        rewardPool = IRewardPool(_rewardPool);

        _setVoteDelegation(_keeper);
    }

    // Checks that caller is either owner or keeper.
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
     * @dev Updates address of the Qi Batch.
     * @param _newRewardPool new rewardPool address.
     */
    function setRewardPool(address _newRewardPool) external onlyOwner {
        emit NewRewardPool(rewardPool, _newRewardPool);
        rewardPool = IRewardPool(_newRewardPool);
    }

    // Transfer reward pool ownership
    function transferRewardPoolOwnership(address _newOwner) external onlyOwner {
        rewardPool.transferOwnership(_newOwner);
    }

    // set voter params 
    function setVoterParams(IDelegateManager _delegationManager, bytes32 _newId) external onlyManager {
        emit NewVoterParams(_delegationManager, _newId);
        delegateManager = _delegationManager;
        id = _newId;
    }

   // set vote delegation 
    function setVoteDelegation (address _voter) external onlyManager {
        _setVoteDelegation(_voter);
    }
    function _setVoteDelegation(address _voter) internal {
        emit NewVoter(_voter);
        delegateManager.setDelegate(id, _voter);
    }

    // clear vote delegation 
    function clearVoteDelegation() external onlyManager {
        delegateManager.clearDelegate(id);
    }

    function currentVoter() external view returns (address) {
        return delegateManager.delegation(address(this), id);
    }
}
