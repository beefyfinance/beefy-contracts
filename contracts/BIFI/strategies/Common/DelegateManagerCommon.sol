// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/common/IDelegateManagerCommon.sol";
import "./StratFeeManager.sol";

abstract contract DelegateManagerCommon is StratFeeManager {

    /**
     * @dev Contracts:
     * {delegateManagerCommon} - Address for Snapshot delegation
     */
  
    IDelegateManagerCommon public delegateManager = IDelegateManagerCommon(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);
    bytes32 public id; // Snapshot ENS
    
    // Contract Events
    event NewVoter(address newVoter);
    event NewVoterParams(IDelegateManagerCommon newDelegateManager, bytes32 newId);

    /**
     * @dev Initializes the base strategy.
     */
    constructor (bytes32 _id, address _voter) {
        id = _id;
        _setVoteDelegation(_voter);
    }

    // set voter params 
    function setVoterParams(IDelegateManagerCommon _delegationManager, bytes32 _newId) external onlyManager {
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
