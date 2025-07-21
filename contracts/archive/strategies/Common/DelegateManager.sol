// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";

import "../../interfaces/common/IDelegateManager.sol";

contract DelegateManager is Ownable, Pausable {

    /**
     * @dev Contracts:
     * {delegateManager} - Address for Snapshot delegation
     */
  
    IDelegateManager public delegateManager = IDelegateManager(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);
    bytes32 public id; // Snapshot ENS
    address public keeper;
    
    // Contract Events
    event NewVoter(address newVoter);
    event NewVoterParams(IDelegateManager newDelegateManager, bytes32 newId);
    event NewKeeper(address oldKeeper, address newKeeper);

    /**
     * @dev Initializes the base strategy.
     */
   constructor(
        address _keeper,
        bytes32 _id
    ) {
        keeper = _keeper;
        id = _id;

        _setVoteDelegation(_keeper);
    }

    // Checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // Set a new Keeper
    function setKeeper(address _keeper) external onlyManager {
        emit NewKeeper(keeper, _keeper);
        keeper = _keeper;
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
