// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./IJoeChef.sol";
import "./IJoeStrategy.sol";

contract ChefManager is Initializable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @dev Beefy Contracts:
     * {joeChef} - Address of the boosted chef
     * {keeper} - Address to manage a few lower risk features of the strat.
     * {rewardPool} - Address for distributing locked want rewards.
     */
    IJoeChef public joeChef;
    address public keeper;
    address public rewardPool;

    mapping(uint256 => address) public whitelistedStrategy;
    mapping(address => address) public replacementStrategy;

    /**
     * @dev Initializes the base strategy.
     * @param _joeChef address of the boosted chef.
     * @param _keeper address to use as alternative owner.
     * @param _rewardPool address of reward pool.
     */
    function managerInitialize(
        address _joeChef,
        address _keeper,
        address _rewardPool
    ) internal initializer {
        __Ownable_init();

        joeChef = IJoeChef(_joeChef);
        keeper = _keeper;
        rewardPool = _rewardPool;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // checks that caller is the strategy assigned to a specific gauge.
    modifier onlyWhitelist(uint256 _pid) {
        require(whitelistedStrategy[_pid] == msg.sender, "!whitelisted");
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

     /**
     * @dev Whitelists a strategy address to interact with the Gauge Staker and gives approvals.
     * @param _strategy new strategy address.
     */
    function whitelistStrategy(address _strategy) external onlyManager {
        IERC20Upgradeable _want = IJoeStrategy(_strategy).want();
        uint256 _pid = IJoeStrategy(_strategy).pid();
        (uint256 stratBal,,) = joeChef.userInfo(_pid, address(this));
        require(stratBal == 0, "!inactive");

        _want.safeApprove(address(joeChef), 0);
        _want.safeApprove(address(joeChef), type(uint256).max);
        whitelistedStrategy[_pid] = _strategy;
    }

    /**
     * @dev Removes a strategy address from the whitelist and remove approvals.
     * @param _strategy remove strategy address from whitelist.
     */
    function blacklistStrategy(address _strategy) external onlyManager {
        IERC20Upgradeable _want = IJoeStrategy(_strategy).want();
        uint256 _pid = IJoeStrategy(_strategy).pid();
        _want.safeApprove(address(joeChef), 0);
        whitelistedStrategy[_pid] = address(0);
    }

    /**
     * @dev Prepare a strategy to be retired and replaced with another.
     * @param _oldStrategy strategy to be replaced.
     * @param _newStrategy strategy to be implemented.
     */
    function proposeStrategy(address _oldStrategy, address _newStrategy) external onlyManager {
        require(IJoeStrategy(_oldStrategy).pid() == IJoeStrategy(_newStrategy).pid(), "!pid");
        replacementStrategy[_oldStrategy] = _newStrategy;
    }

    /**
     * @dev Switch over whitelist from one strategy to another for a gauge.
     * @param _pid pid for which the new strategy will be whitelisted.
     */
    function upgradeStrategy(uint256 _pid) external onlyWhitelist(_pid) {
        whitelistedStrategy[_pid] = replacementStrategy[msg.sender];
    }

    /**
    * WIP 
    * Will give us an opportunity to vote via snapshot with veJOE
    */
   // function isValidSignature(
   //     bytes32 _hash,
   //     bytes calldata _signature
   //) external override view returns (bytes4) {
   //     // Validate signatures
   //     if (recoverSigner(_hash, _signature) == keeper) {
   //         return 0x1626ba7e;
   //     } else {
   //         return 0xffffffff;
   //     }  
   // } 

   
}
