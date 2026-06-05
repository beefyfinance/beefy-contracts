// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../../interfaces/common/gauge/IGauge.sol";
import "../../interfaces/common/gauge/IGaugeStrategy.sol";
import "../../interfaces/common/gauge/IVeWantFeeDistributor.sol";

contract GaugeManager is Initializable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /**
     * @dev Beefy Contracts:
     * {feeDistributor} - Address of the fee distributor for veWant rewards.
     * {gaugeProxy} - Address for voting on gauge weightings.
     * {keeper} - Address to manage a few lower risk features of the strat.
     * {rewardPool} - Address for distributing locked want rewards.
     */
    IVeWantFeeDistributor public feeDistributor;
    IGauge public gaugeProxy;
    address public keeper;
    address public rewardPool;

    mapping(address => address) whitelistedStrategy;
    mapping(address => address) replacementStrategy;

    /**
     * @dev Initializes the base strategy.
     * @param _feeDistributor address of veWant fee distributor.
     * @param _gaugeProxy address of gauge proxy to vote on.
     * @param _keeper address to use as alternative owner.
     * @param _rewardPool address of reward pool.
     */
    function managerInitialize(
        address _feeDistributor,
        address _gaugeProxy,
        address _keeper,
        address _rewardPool
    ) internal initializer {
        __Ownable_init();

        feeDistributor = IVeWantFeeDistributor(_feeDistributor);
        gaugeProxy = IGauge(_gaugeProxy);
        keeper = _keeper;
        rewardPool = _rewardPool;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // checks that caller is the strategy assigned to a specific gauge.
    modifier onlyWhitelist(address _gauge) {
        require(whitelistedStrategy[_gauge] == msg.sender, "!whitelisted");
        _;
    }

    // checks that caller is the reward pool.
    modifier onlyRewardPool() {
        require(msg.sender == rewardPool, "!rewardPool");
        _;
    }

    /**
     * @dev Updates address of the fee distributor.
     * @param _feeDistributor new fee distributor address.
     */
    function setFeeDistributor(address _feeDistributor) external onlyOwner {
        feeDistributor = IVeWantFeeDistributor(_feeDistributor);
    }

    /**
     * @dev Updates address where gauge weighting votes will be placed.
     * @param _gaugeProxy new gauge proxy address.
     */
    function setGaugeProxy(address _gaugeProxy) external onlyOwner {
        gaugeProxy = IGauge(_gaugeProxy);
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
        IERC20Upgradeable _want = IGaugeStrategy(_strategy).want();
        address _gauge = IGaugeStrategy(_strategy).gauge();
        require(IGauge(_gauge).balanceOf(address(this)) == 0, '!inactive');

        _want.safeApprove(_gauge, 0);
        _want.safeApprove(_gauge, type(uint256).max);
        whitelistedStrategy[_gauge] = _strategy;
    }

    /**
     * @dev Removes a strategy address from the whitelist and remove approvals.
     * @param _strategy remove strategy address from whitelist.
     */
    function blacklistStrategy(address _strategy) external onlyManager {
        IERC20Upgradeable _want = IGaugeStrategy(_strategy).want();
        address _gauge = IGaugeStrategy(_strategy).gauge();
        _want.safeApprove(_gauge, 0);
        whitelistedStrategy[_gauge] = address(0);
    }

    /**
     * @dev Prepare a strategy to be retired and replaced with another.
     * @param _oldStrategy strategy to be replaced.
     * @param _newStrategy strategy to be implemented.
     */
    function proposeStrategy(address _oldStrategy, address _newStrategy) external onlyManager {
        require(IGaugeStrategy(_oldStrategy).gauge() == IGaugeStrategy(_newStrategy).gauge(), '!gauge');
        replacementStrategy[_oldStrategy] = _newStrategy;
    }

    /**
     * @dev Switch over whitelist from one strategy to another for a gauge.
     * @param _gauge gauge for which the new strategy will be whitelisted.
     */
    function upgradeStrategy(address _gauge) external onlyWhitelist(_gauge) {
        whitelistedStrategy[_gauge] = replacementStrategy[msg.sender];
    }
}
