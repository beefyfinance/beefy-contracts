// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeERC20Upgradeable, IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { IWrappedNative } from  "../../interfaces/common/IWrappedNative.sol";
import { AbstractFunctions } from "./AbstractFunctions.sol";
import { IFeeConfig } from "../../interfaces/common/IFeeConfig.sol";
import { IBeefyCore } from "../../interfaces/beefy/IBeefyCore.sol";
import { IBeefySwapper } from "../../interfaces/beefy/IBeefySwapper.sol";
import { IBeefyOracle } from "../../interfaces/beefy/IBeefyOracle.sol";
import { IBeefyZapRouter } from "../../interfaces/beefy/IBeefyZapRouter.sol";

/// @title Base strategy
/// @author Beefy, @kexley
/// @notice Base strategy logic
abstract contract BaseStrategy is AbstractFunctions, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct BaseStrategyAddresses {
        address want;
        address vault;
        address core;
        address strategist;
        address[] rewards;
    }

    /// @notice Want token deposited to the vault
    address public want;
    
    /// @notice Vault address
    address public vault;

    /// @notice Core address for the strategy
    IBeefyCore public core;

    /// @notice Strategy deployer's fee recipient
    address public strategist;

    /// @notice Reward tokens to compound
    address[] public rewards;

    /// @notice Tokens to deposit during _addLiquidity()
    address[] public depositTokens;

    /// @notice Native token used to pay fees
    address public native;

    /// @notice Timestamp of the last harvest
    uint256 public lastHarvest;

    /// @notice Total harvested amount not yet vested
    uint256 public totalLocked;

    /// @notice Linear vesting duration for harvested amounts
    uint256 public lockDuration;

    /// @notice Toggle harvests on deposits
    bool public harvestOnDeposit;

    uint256 constant DIVISOR = 1 ether;

    /// @notice Strategy has been harvested
    /// @param harvester Harvest caller
    /// @param wantHarvested Amount of want token profit the strategy has harvested
    /// @param tvl Amount of want tokens now controlled by the strategy
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);

    /// @notice Want tokens have been deposited to the underlying platform
    /// @param tvl Amount of want tokens now controlled by the strategy
    event Deposit(uint256 tvl);

    /// @notice Want tokens have been withdrawn from the underlying platform
    /// @param tvl Amount of want tokens now controlled by the strategy
    event Withdraw(uint256 tvl);

    /// @notice Fees have been charged in the native token
    /// @param callFees Fees going to harvest caller
    /// @param beefyFees Fees going to the Beefy contracts
    /// @param strategistFees Fees going to the strategy deployer
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    /// @notice New vault set
    /// @param vault New vault address
    event SetVault(address vault);

    /// @notice New core set
    /// @param core New core address
    event SetCore(address core);

    /// @notice New strategist set
    /// @param strategist New strategist address
    event SetStrategist(address strategist);

    /// @notice The strategy is paused
    error StrategyPaused();

    /// @notice Caller is not a manager
    error NotManager();

    /// @notice Check if strategy is paused
    modifier ifNotPaused() {
        if (paused() || core.globalPause()) revert StrategyPaused();
        _;
    }

    /// @dev Check if caller is manager
    modifier onlyManager() {
        _checkManager();
        _;
    }

    /// @dev Check if caller is manager
    function _checkManager() internal view {
        if (msg.sender != owner() && msg.sender != keeper()) revert NotManager();
    }

    /// @dev Initialize the Base Strategy
    function __BaseStrategy_init(
        BaseStrategyAddresses calldata _baseStrategyAddresses
    ) internal onlyInitializing {
        __Ownable_init();
        __Pausable_init();
        want = _baseStrategyAddresses.want;
        vault = _baseStrategyAddresses.vault;
        core = IBeefyCore(_baseStrategyAddresses.core);
        strategist = _baseStrategyAddresses.strategist;
        native = core.native();
        lockDuration = 6 hours;

        for (uint256 i; i < _baseStrategyAddresses.rewards.length; ++i) {
            addReward(_baseStrategyAddresses.rewards[i]);
        }
    }

    /* -------------------------------- BASIC WRITE FUNCTIONS -------------------------------- */

    /// @notice Deposit all want on this contract to the underlying platform
    function deposit() public ifNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            _deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    /// @notice Withdraw some want and transfer to the vault
    /// @param _amount Amount to withdraw from this contract
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            _withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20Upgradeable(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    /// @notice Harvest before a new external deposit if toggled on
    function beforeDeposit() external virtual {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
    }

    /// @notice Harvest rewards and compound back into more want tokens
    function harvest() external {
        _harvest(tx.origin, false);
    }

    /// @notice Harvest rewards and compound back into more want tokens
    /// @param _callFeeRecipient Recipient for the harvest caller fees
    function harvest(address _callFeeRecipient) external {
        _harvest(_callFeeRecipient, false);
    }

    /// @dev Claim all rewards, swap them to native, charge fees and then swap to want
    /// @param _callFeeRecipient Recipient for the harvest caller fees
    /// @param _onDeposit Toggle for not depositing twice in a harvest on deposit
    function _harvest(address _callFeeRecipient, bool _onDeposit) internal ifNotPaused {
        uint256 wantBalanceBefore = balanceOfWant();
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));
        if (nativeBal > swapper().minimumAmount(native)) {
            _chargeFees(_callFeeRecipient);
            _swapNativeToWant();
            uint256 wantHarvested = balanceOfWant() - wantBalanceBefore;
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;

            if (!_onDeposit) {
                deposit();
            }

            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    /// @dev Swap all rewards to native so fees can be accurately charged
    /// Can be overridden in child contract if needed
    function _swapRewardsToNative() internal virtual {
        for (uint256 i; i < rewards.length; ++i) {
            address token = rewards[i];
            if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                IWrappedNative(native).deposit{value: address(this).balance}();
            } else {
                uint256 amount = IERC20Upgradeable(token).balanceOf(address(this));
                if (amount > swapper().minimumAmount(token)) {
                    IERC20Upgradeable(token).forceApprove(address(swapper()), amount);
                    swapper().swap(token, native, amount);
                }
            }
        }
    }

    /// @dev Charge fees and send to recipients
    /// @param _callFeeRecipient Recipient for the harvest caller fees
    function _chargeFees(address _callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = beefyFeeConfig().getFees(address(this));
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(_callFeeRecipient, callFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(strategist, strategistFeeAmount);

        uint256 beefyFeeAmount = nativeBal - callFeeAmount - strategistFeeAmount;
        IERC20Upgradeable(native).safeTransfer(beefyFeeRecipient(), beefyFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    /// @dev Swap the remaining native to want tokens, either directly or by swapping to 
    /// depositTokens and adding liquidity
    function _swapNativeToWant() internal {
        uint256[] memory amounts = _getDepositAmounts();
        for (uint256 i; i < depositTokens.length; ++i) {
            if (depositTokens[i] != native && amounts[i] > 0) {
                IERC20Upgradeable(native).forceApprove(address(swapper()), amounts[i]);
                swapper().swap(native, depositTokens[i], amounts[i]);
            }
        }
        _addLiquidity();
    }

    /* ------------------------------------ VIEW FUNCTIONS ------------------------------------ */

    /// @notice Number of rewards that this strategy receives
    function rewardsLength() external view returns (uint256) {
        return rewards.length;
    }

    /// @notice Remaining amount locked from a harvest, decaying linearly
    function lockedProfit() public view returns (uint256) {
        if (lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < lockDuration ? lockDuration - elapsed : 0;
        return totalLocked * remaining / lockDuration;
    }

    /// @notice Total amount of want controlled by this strategy, less the locked harvested amount
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    /// @notice Amount of want held directly on this address
    function balanceOfWant() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    function depositFee() public virtual view returns (uint256) {
        return 0;
    }

    function withdrawFee() public virtual view returns (uint256) {
        return 0;
    }

    /* -------------------------------- CORE VIEW FUNCTIONS -------------------------------- */

    /// @notice Keeper for managing less critical admin functions
    function keeper() public view returns (address) {
        return core.keeper();
    }

    /// @notice Swapper used to swap tokens
    function swapper() public view returns (IBeefySwapper) {
        return core.swapper();
    }

    /// @notice Oracle used to price tokens
    function oracle() public view returns (IBeefyOracle) {
        return core.oracle();
    }

    /// @notice Fee recipient for Beefy
    function beefyFeeRecipient() public view returns (address) {
        return core.beefyFeeRecipient();
    }

    /// @notice Fee configurator
    function beefyFeeConfig() public view returns (IFeeConfig) {
        return core.beefyFeeConfig();
    }

    /* ---------------------------------- MANAGER FUNCTIONS ---------------------------------- */

    /// @notice Pause the strategy and pull all funds out of the underlying platform
    function panic() public onlyManager {
        pause();
        _emergencyWithdraw();
    }

    /// @notice Pause the strategy
    function pause() public onlyManager {
        _pause();
    }

    /// @notice Unpause the strategy and deposit funds back into the underlying platform
    function unpause() external onlyManager {
        _unpause();
        deposit();
    }

    /// @notice Add a reward to be swapped
    /// @dev New reward token should not be a critical one used by the strategy
    /// @param _token New reward token
    function addReward(address _token) public onlyManager {
        _verifyRewardToken(_token);
        rewards.push(_token);
    }

    /// @notice Remove a reward from the list
    /// @param _i Position of the reward in the list
    function removeReward(uint256 _i) external onlyManager {
        rewards[_i] = rewards[rewards.length - 1];
        rewards.pop();
    }

    /// @notice Remove all rewards from the list
    function resetRewards() external onlyManager {
        delete rewards;
    }

    /// @notice Toggle harvesting before external deposits
    /// @param _harvestOnDeposit Toggle harvests on deposits
    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    /// @notice Set linear vesting duration for harvested amounts
    /// @param _duration Linear vesting duration in seconds
    function setLockDuration(uint256 _duration) external onlyManager {
        lockDuration = _duration;
    }

    /// @notice Set a new strategy deployer fee recipient
    /// @param _strategist New strategy deployer fee recipient
    function setStrategist(address _strategist) external {
        if (msg.sender != strategist && msg.sender != owner() && msg.sender != keeper()) 
            revert NotManager();
        strategist = _strategist;
        emit SetStrategist(_strategist);
    }

    /// @notice Set the stored swap steps for the route between many tokens
    /// @param _fromTokens Tokens to swap from
    /// @param _toTokens Tokens to swap to
    /// @param _swapSteps Swap steps to store
    function setSwapSteps(
        address[] calldata _fromTokens,
        address[] calldata _toTokens,
        IBeefyZapRouter.Step[][] calldata _swapSteps
    ) external onlyManager {
        swapper().setSwapSteps(_fromTokens, _toTokens, _swapSteps);
    }

    /// @notice Set a sub oracle and data for multiple tokens
    /// @param _tokens Address of the tokens being fetched
    /// @param _oracles Address of the libraries used to calculate the price
    /// @param _datas Payload specific to the tokens that will be used by the library
    function setOracles(
        address[] calldata _tokens,
        address[] calldata _oracles,
        bytes[] calldata _datas
    ) external onlyManager {
        oracle().setOracles(_tokens, _oracles, _datas);
    }

    /* ---------------------------------- OWNER FUNCTIONS ---------------------------------- */

    /// @notice Set the vault address
    /// @param _vault New vault address
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit SetVault(_vault);
    }

    /// @notice Set the core address
    /// @param _core New core address
    function setCore(address _core) external onlyOwner {
        core = IBeefyCore(_core);
        emit SetCore(_core);
    }

    /// @notice Retire strategy and send all funds back to vault
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _emergencyWithdraw();
        IERC20Upgradeable(want).transfer(vault, balanceOfWant());
    }

    /* ---------------------------------------- EXTRAS ---------------------------------------- */

    /// @dev Allow unwrapped native to be sent to this address
    receive () payable external {}

    uint256[49] private __gap;
}