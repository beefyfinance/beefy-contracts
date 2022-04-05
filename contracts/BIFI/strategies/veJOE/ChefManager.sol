// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "./IJoeChef.sol";
import "./IJoeStrategy.sol";

contract ChefManager is Initializable, OwnableUpgradeable, PausableUpgradeable, IERC1271Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ECDSAUpgradeable for bytes32;

    /**
     * @dev Beefy Contracts:
     * {joeChef} - Address of the boosted chef
     * {keeper} - Address to manage a few lower risk features of the strat.
     * {rewardPool} - Address for distributing locked want rewards.
     */
    address public keeper;
    address public joeBatch;

    // Fee integers
    uint256 public beJoeShare;

    mapping(address => mapping (uint256 => address)) public whitelistedStrategy;
    mapping(address => address) public replacementStrategy;

    event NewKeeper(address oldKeeper, address newKeeper);
    event NewBeJoeShare(uint256 oldShare, uint256 newShare);
    event NewJoeBatch(address oldBatch, address newBatch);

    /**
     * @dev Initializes the base strategy.
     * @param _keeper address to use as alternative owner.
     */
    function managerInitialize(
        address _keeper,
        address _joeBatch,
        uint256 _beJoeShare
    ) internal initializer {
        __Ownable_init();

        keeper = _keeper;
        joeBatch = _joeBatch;

        // Cannot be more than 10%
        require(_beJoeShare <= 1000, "Too Much");
        beJoeShare = _beJoeShare;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // checks that caller is the strategy assigned to a specific gauge.
    modifier onlyWhitelist(address _joeChef, uint256 _pid) {
        require(whitelistedStrategy[_joeChef][_pid] == msg.sender, "!whitelisted");
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
     * @dev Updates address of the Joe Batch.
     * @param _joeBatch new joeBatch address.
     */
    function setJoeBatch(address _joeBatch) external onlyOwner {
        emit NewJoeBatch(joeBatch, _joeBatch);
        joeBatch = _joeBatch;
        
    }

    /**
     * @dev Updates share for the Joe Batch.
     * @param _newBeJoeShare new Joe share.
     */
    function setbeJoeShare(uint256 _newBeJoeShare) external onlyManager {
        require(_newBeJoeShare <= 1000, "too much");
        emit NewBeJoeShare(beJoeShare, _newBeJoeShare);
        beJoeShare = _newBeJoeShare;
    }

     /**
     * @dev Whitelists a strategy address to interact with the Boosted Chef and gives approvals.
     * @param _strategy new strategy address.
     */
    function whitelistStrategy(address _strategy) external onlyManager {
        IERC20Upgradeable _want = IJoeStrategy(_strategy).want();
        uint256 _pid = IJoeStrategy(_strategy).poolId();
        address _joeChef = IJoeStrategy(_strategy).chef();
        (uint256 stratBal,,) = IJoeChef(_joeChef).userInfo(_pid, address(this));
        require(stratBal == 0, "!inactive");

        _want.safeApprove(_joeChef, 0);
        _want.safeApprove(_joeChef, type(uint256).max);
        whitelistedStrategy[_joeChef][_pid] = _strategy;
    }

    /**
     * @dev Removes a strategy address from the whitelist and remove approvals.
     * @param _strategy remove strategy address from whitelist.
     */
    function blacklistStrategy(address _strategy) external onlyManager {
        IERC20Upgradeable _want = IJoeStrategy(_strategy).want();
        uint256 _pid = IJoeStrategy(_strategy).poolId();
        address _joeChef = IJoeStrategy(_strategy).chef();
        _want.safeApprove(_joeChef, 0);
        whitelistedStrategy[_joeChef][_pid] = address(0);
    }

    /**
     * @dev Prepare a strategy to be retired and replaced with another.
     * @param _oldStrategy strategy to be replaced.
     * @param _newStrategy strategy to be implemented.
     */
    function proposeStrategy(address _oldStrategy, address _newStrategy) external onlyManager {
        require(IJoeStrategy(_oldStrategy).poolId() == IJoeStrategy(_newStrategy).poolId(), "!pid");
        replacementStrategy[_oldStrategy] = _newStrategy;
    }

    /**
     * @dev Switch over whitelist from one strategy to another for a gauge.
     * @param _pid pid for which the new strategy will be whitelisted.
     */
    function upgradeStrategy(address _joeChef, uint256 _pid) external onlyWhitelist(_joeChef, _pid) {
        whitelistedStrategy[_joeChef][_pid] = replacementStrategy[msg.sender];
    }

    /**
    * Will give us an opportunity to vote via snapshot with veJOE
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
