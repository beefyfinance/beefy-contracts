// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import "../strategies/Multi/CascadingAccessControl.sol";
import "../interfaces/beefy/IMultiStrategy.sol";
import "../interfaces/common/IFeeConfig.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract VaultManager is Initializable, ERC4626Upgradeable, CascadingAccessControl {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct StrategyParams {
        uint256 activation; // Timestamp of strategy activation.
        uint256 debtRatio; // Allocation in BPS of vault's total assets.
        uint256 allocated; // Amount of capital allocated to this strategy.
        uint256 gains; // Total returns that strategy has realized.
        uint256 losses; // Total losses that strategy has realized.
        uint256 lastReport; // Timestamp of the last time the strategy reported in.
    }

    // Mapping strategies to their strategy parameters.
    mapping(address => StrategyParams) public strategies;
    // Ordering that `withdraw` uses to determine which strategies to pull funds from.
    address[] public withdrawalQueue;
    // The unit for calculating profit degradation.
    uint256 public constant DEGRADATION_COEFFICIENT = 1e18;
    // Basis point unit, for calculating slippage and strategy allocations.
    uint256 public constant PERCENT_DIVISOR = 10_000;
    // The maximum amount of assets the vault can hold while still allowing deposits.
    uint256 public tvlCap;
    // Sum of debtRatio across all strategies (in BPS, <= 10k).
    uint256 public totalDebtRatio;
    // Amount of tokens that have been allocated to all strategies.
    uint256 public totalAllocated;
    // Timestamp of last report from any strategy.
    uint256 public lastReport;
    // Emergency shutdown - when true funds are pulled out of strategies to the vault.
    bool public emergencyShutdown;
    // Max slippage(loss) allowed when withdrawing, in BPS (0.01%).
    uint256 public withdrawMaxLoss = 1;
    // Rate per second of degradation. DEGRADATION_COEFFICIENT is 100% per second.
    uint256 public lockedProfitDegradation = DEGRADATION_COEFFICIENT / 6 hours;
    // How much profit is locked and cant be withdrawn.
    uint256 public lockedProfit;
    // Beefy fee recipient address.
    address public beefyFeeRecipient;
    // Fee split configurator for the strategies.
    address public beefyFeeConfig;

    bytes32 internal constant ADMIN = keccak256("ADMIN");
    bytes32 internal constant GUARDIAN = keccak256("GUARDIAN");

    bytes32[] private _cascadingAccessRoles = [
        bytes32(0),
        ADMIN,
        GUARDIAN
    ];

    event AddStrategy(address indexed strategy, uint256 debtRatio);
    event SetStrategyDebtRatio(address indexed strategy, uint256 debtRatio);
    event SetWithdrawalQueue(address[] withdrawalQueue);
    event SetWithdrawMaxLoss(uint256 withdrawMaxLoss);
    event SetLockedProfitDegradation(uint256 degradation);
    event SetTvlCap(uint256 newTvlCap);
    event SetBeefyFeeRecipient(address beefyFeeRecipient);
    event SetBeefyFeeConfig(address beefyFeeConfig);
    event EmergencyShutdown(bool active);
    event InCaseTokensGetStuck(address token, uint256 amount);

    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own 'moo' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     * @param _tvlCap Initial deposit cap for scaling TVL safely.
     */
    function __VaultManager_init(
        uint256 _tvlCap,
        address _timelock,
        address _dev,
        address _keeper,
        address _beefyFeeRecipient,
        address _beefyFeeConfig
    ) public onlyInitializing {
        tvlCap = _tvlCap;
        beefyFeeRecipient = _beefyFeeRecipient;
        beefyFeeConfig = _beefyFeeConfig;
        lastReport = block.timestamp;

        _grantRole(_cascadingAccessRoles[0], _timelock);
        _grantRole(_cascadingAccessRoles[1], _dev);
        _grantRole(_cascadingAccessRoles[2], _keeper);
    }

    /**
     * @dev It checks that the caller is an active strategy.
     */
    modifier onlyStrategy() {
        require(strategies[msg.sender].activation != 0, "!activeStrategy");
        _;
    }

    /**
     * @dev Adds a new strategy to the vault with a given allocation amount in basis points.
     * @param strategy The strategy to add.
     * @param debtRatio The strategy allocation in basis points.
     */
    function addStrategy(address strategy, uint256 debtRatio) external atLeastRole(ADMIN) {
        require(!emergencyShutdown, "emergencyShutdown");
        require(strategy != address(0), "zeroAddress");
        require(strategies[strategy].activation == 0, "activeStrategy");
        require(address(this) == IMultiStrategy(strategy).vault(), "!vault");
        require(asset() == address(IMultiStrategy(strategy).want()), "!want");
        require(debtRatio + totalDebtRatio <= PERCENT_DIVISOR, ">maxAlloc");

        strategies[strategy] = StrategyParams({
            activation: block.timestamp,
            debtRatio: debtRatio,
            allocated: 0,
            gains: 0,
            losses: 0,
            lastReport: block.timestamp
        });

        totalDebtRatio += debtRatio;
        withdrawalQueue.push(strategy);
        emit AddStrategy(strategy, debtRatio);
    }

    /**
     * @dev Sets the allocation points for a given strategy.
     * @param strategy The strategy to set.
     * @param debtRatio The strategy allocation in basis points.
     */
    function setStrategyDebtRatio(address strategy, uint256 debtRatio) external atLeastRole(GUARDIAN) {
        require(strategies[strategy].activation != 0, "!activeStrategy");
        totalDebtRatio -= strategies[strategy].debtRatio;
        strategies[strategy].debtRatio = debtRatio;
        totalDebtRatio += debtRatio;
        require(totalDebtRatio <= PERCENT_DIVISOR, ">maxAlloc");
        emit SetStrategyDebtRatio(strategy, debtRatio);
    }

    /**
     * @dev Sets the withdrawalQueue to match the addresses and order specified.
     * @param _withdrawalQueue The new withdrawalQueue to set to.
     */
    function setWithdrawalQueue(address[] calldata _withdrawalQueue) external atLeastRole(GUARDIAN) {
        uint256 queueLength = _withdrawalQueue.length;
        require(queueLength != 0, "emptyQueue");

        delete withdrawalQueue;
        for (uint256 i; i < queueLength;) {
            address strategy = _withdrawalQueue[i];
            StrategyParams storage params = strategies[strategy];
            require(params.activation != 0, "!activeStrategy");
            withdrawalQueue.push(strategy);
            unchecked { ++i; }
        }
        emit SetWithdrawalQueue(withdrawalQueue);
    }

    /**
     * @dev Sets the withdrawMaxLoss which is the maximum allowed slippage.
     * @param newWithdrawMaxLoss The new loss maximum, in basis points, when withdrawing.
     */
    function setWithdrawMaxLoss(uint256 newWithdrawMaxLoss) external atLeastRole(GUARDIAN) {
        require(newWithdrawMaxLoss <= PERCENT_DIVISOR, ">maxLoss");
        withdrawMaxLoss = newWithdrawMaxLoss;
        emit SetWithdrawMaxLoss(withdrawMaxLoss);
    }

    /**
     * @dev Changes the locked profit degradation.
     * @param degradation The rate of degradation in percent per second scaled to 1e18.
     */
    function setLockedProfitDegradation(uint256 degradation) external atLeastRole(GUARDIAN) {
        require(degradation <= DEGRADATION_COEFFICIENT, ">maxDegradation");
        lockedProfitDegradation = degradation;
        emit SetLockedProfitDegradation(degradation);
    }

    /**
     * @dev Sets the vault tvl cap (the max amount of assets held by the vault).
     * @param newTvlCap The new tvl cap.
     */
    function setTvlCap(uint256 newTvlCap) public atLeastRole(GUARDIAN) {
        tvlCap = newTvlCap;
        emit SetTvlCap(tvlCap);
    }

     /**
     * @dev Helper function to remove TVL cap.
     */
    function removeTvlCap() external atLeastRole(GUARDIAN) {
        setTvlCap(type(uint256).max);
    }

    /**
     * @dev Sets the beefy fee recipient address to receive fees.
     * @param newBeefyFeeRecipient The new beefy fee recipient address.
     */
    function setBeefyFeeRecipient(address newBeefyFeeRecipient) external atLeastRole(GUARDIAN) {
        beefyFeeRecipient = newBeefyFeeRecipient;
        emit SetBeefyFeeRecipient(beefyFeeRecipient);
    }

    /**
     * @dev Sets the beefy fee config address to change fee configurator.
     * @param newBeefyFeeConfig The new beefy fee config address.
     */
    function setBeefyFeeConfig(address newBeefyFeeConfig) external atLeastRole(GUARDIAN) {
        beefyFeeConfig = newBeefyFeeConfig;
        emit SetBeefyFeeConfig(beefyFeeConfig);
    }

    /**
     * @dev Activates or deactivates Vault mode where all Strategies go into full
     * withdrawal.
     * During Emergency Shutdown:
     * 1. No Users may deposit into the Vault (but may withdraw as usual).
     * 2. New Strategies may not be added.
     * 3. Each Strategy must pay back their debt as quickly as reasonable to
     * minimally affect their position.
     *
     * If true, the Vault goes into Emergency Shutdown. If false, the Vault
     * goes back into Normal Operation.
     * @param active If emergencyShutdown is active or not.
     */
    function setEmergencyShutdown(bool active) external atLeastRole(GUARDIAN) {
        emergencyShutdown = active;
        emit EmergencyShutdown(emergencyShutdown);
    }

    /**
     * @dev Cancels the line of credit to the strategy. On next report the strategy will 
     * return all funds to the vault.
     */
    function revokeStrategy() external onlyStrategy {
        address stratAddr = msg.sender;
        totalDebtRatio -= strategies[stratAddr].debtRatio;
        strategies[stratAddr].debtRatio = 0;
        emit SetStrategyDebtRatio(stratAddr, 0);
    }

    /**
     * @dev Fetch fees from the Fee Config contract.
     */
    function getFees(address strategy) internal view returns (IFeeConfig.FeeCategory memory) {
        return IFeeConfig(beefyFeeConfig).getFees(strategy);
    }

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param token Address of the asset to rescue.
     */
    function inCaseTokensGetStuck(address token) external atLeastRole(GUARDIAN) {
        require(token != asset(), "!asset");

        uint256 amount = IERC20Upgradeable(token).balanceOf(address(this));
        IERC20Upgradeable(token).safeTransfer(msg.sender, amount);
        emit InCaseTokensGetStuck(token, amount);
    }

    function cascadingAccessRoles() public view override returns (bytes32[] memory) {
        return _cascadingAccessRoles;
    }
}
