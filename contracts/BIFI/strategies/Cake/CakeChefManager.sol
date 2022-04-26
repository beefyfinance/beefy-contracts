// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "./ICakeV2Chef.sol";
import "./ICakeBoostStrategy.sol";

interface IDelegateManager {
    function setDelegate(bytes32 _id, address _voter) external;
    function clearDelegate(bytes32 _id) external;
    function delegation(address _voteHolder, bytes32 _id) external view returns (address);
}

contract CakeChefManager is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /**
     * @dev Beefy Contracts:
     * {CakeChef} - Address of the boosted chef
     * {keeper} - Address to manage a few lower risk features of the strat.
     * {cakeBatch} - Address for distributing locked want rewards.
     * {delegateManager} - Address for Snapshot delegation
     */
    address public keeper;
    address public cakeBatch;
    IDelegateManager public delegateManager = IDelegateManager(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);
    bytes32 public id = bytes32("cake.eth"); // Cake's Snapshot ENS

    // beCake fee taken from strats
    uint256 public beCakeShare;

    // Strategy mapping 
    mapping(address => mapping (uint256 => address)) public whitelistedStrategy;
    mapping(address => address) public replacementStrategy;

    // Contract Events
    event NewKeeper(address oldKeeper, address newKeeper);
    event NewBeCakeShare(uint256 oldShare, uint256 newShare);
    event NewCakeBatch(address oldBatch, address newBatch);
    event NewVoter(address newVoter);
    event NewVoterParams(IDelegateManager newDelegatManager, bytes32 newId);

    /**
     * @dev Initializes the base strategy.
     * @param _keeper address to use as alternative owner.
     */
   constructor(
        address _keeper,
        address _cakeBatch,
        uint256 _beCakeShare
    ) {

        keeper = _keeper;
        cakeBatch = _cakeBatch;

        // Cannot be more than 10%
        require(_beCakeShare <= 1000, "Too Much");
        beCakeShare = _beCakeShare;

        // Keeper is the default voter
        _setVoteDelegation(_keeper);
    }

    // Checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // Checks that caller is the strategy assigned to a specific PoolId in a boosted chef.
    modifier onlyWhitelist(address _cakeChef, uint256 _pid) {
        require(whitelistedStrategy[_cakeChef][_pid] == msg.sender, "!whitelisted");
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
     * @dev Updates address of the Cake Batch.
     * @param _cakeBatch new cakeBatch address.
     */
    function setCakeBatch(address _cakeBatch) external onlyOwner {
        emit NewCakeBatch(cakeBatch, _cakeBatch);
        cakeBatch = _cakeBatch;
        
    }

    /**
     * @dev Updates share for the Cake Batch.
     * @param _newBeCakeShare new Cake share.
     */
    function setBeCakeShare(uint256 _newBeCakeShare) external onlyManager {
        require(_newBeCakeShare <= 1000, "too much");
        emit NewBeCakeShare(beCakeShare, _newBeCakeShare);
        beCakeShare = _newBeCakeShare;
    }

     /**
     * @dev Whitelists a strategy address to interact with the Boosted Chef and gives approvals.
     * @param _strategy new strategy address.
     */
    function whitelistStrategy(address _strategy) external onlyManager {
        IERC20 _want = ICakeBoostStrategy(_strategy).want();
        uint256 _pid = ICakeBoostStrategy(_strategy).poolId();
        address _cakeChef = ICakeBoostStrategy(_strategy).chef();
        (uint256 stratBal,,) = ICakeV2Chef(_cakeChef).userInfo(_pid, address(this));
        require(stratBal == 0, "!inactive");

        _want.safeApprove(_cakeChef, 0);
        _want.safeApprove(_cakeChef, type(uint256).max);
        whitelistedStrategy[_cakeChef][_pid] = _strategy;
    }

    /**
     * @dev Removes a strategy address from the whitelist and remove approvals.
     * @param _strategy remove strategy address from whitelist.
     */
    function blacklistStrategy(address _strategy) external onlyManager {
        IERC20 _want = ICakeBoostStrategy(_strategy).want();
        uint256 _pid = ICakeBoostStrategy(_strategy).poolId();
        address _cakeChef = ICakeBoostStrategy(_strategy).chef();
        _want.safeApprove(_cakeChef, 0);
        whitelistedStrategy[_cakeChef][_pid] = address(0);
    }

    /**
     * @dev Prepare a strategy to be retired and replaced with another.
     * @param _oldStrategy strategy to be replaced.
     * @param _newStrategy strategy to be implemented.
     */
    function proposeStrategy(address _oldStrategy, address _newStrategy) external onlyManager {
        require(ICakeBoostStrategy(_oldStrategy).poolId() == ICakeBoostStrategy(_newStrategy).poolId(), "!pid");
        replacementStrategy[_oldStrategy] = _newStrategy;
    }

    /**
     * @dev Switch over whitelist from one strategy to another for a gauge.
     * @param _pid pid for which the new strategy will be whitelisted.
     */
    function upgradeStrategy(address _cakeChef, uint256 _pid) external onlyWhitelist(_cakeChef, _pid) {
        whitelistedStrategy[_cakeChef][_pid] = replacementStrategy[msg.sender];
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
