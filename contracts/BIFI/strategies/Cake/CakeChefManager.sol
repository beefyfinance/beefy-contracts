// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/utils/math/SafeMath.sol";
import "@openzeppelin-4/contracts/interfaces/IERC1271.sol";
import "@openzeppelin-4/contracts/utils/cryptography/ECDSA.sol";

import "./ICakeV2Chef.sol";
import "./ICakeBoostStrategy.sol";

contract CakeChefManager is Ownable, Pausable, IERC1271 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /**
     * @dev Beefy Contracts:
     * {CakeChef} - Address of the boosted chef
     * {keeper} - Address to manage a few lower risk features of the strat.
     * {cakeBatch} - Address for distributing locked want rewards.
     */
    address public keeper;
    address public cakeBatch;

    // beCake fee taken from strats
    uint256 public beCakeShare;

    // Strategy mapping 
    mapping(address => mapping (uint256 => address)) public whitelistedStrategy;
    mapping(address => address) public replacementStrategy;

    event NewKeeper(address oldKeeper, address newKeeper);
    event NewBeCakeShare(uint256 oldShare, uint256 newShare);
    event NewCakeBatch(address oldBatch, address newBatch);

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

    /**
    * Will give us an opportunity to vote via snapshot with veCake
    */
    function isValidSignature(
        bytes32 _messageHash,
        bytes calldata _signature
   ) external override view returns (bytes4) {
        // Validate signatures
        address signer = _messageHash.recover(_signature);
        if (signer == keeper || signer == owner()) {
            return 0x1626ba7e;
        } else {
            return 0xffffffff;
        }  
    }    
}
