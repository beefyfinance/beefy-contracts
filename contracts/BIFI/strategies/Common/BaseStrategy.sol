// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeERC20Upgradeable, IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IWrappedNative } from  "../../interfaces/common/IWrappedNative.sol";
import { StrategySwapper } from "./StrategySwapper.sol";
import { StratFeeManagerInitializable, IFeeConfig } from "./StratFeeManagerInitializable.sol";

/// @title Base strategy
/// @author Beefy, @kexley
/// @notice Base strategy logic
abstract contract BaseStrategy is StrategySwapper, StratFeeManagerInitializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Struct of required addresses
    struct BaseStrategyAddresses {
        address want;
        address native;
        address[] rewards;
        address beefySwapper;
    }

    /// @notice Want token deposited to the vault
    address public want;

    /// @notice Native token used to pay fees
    address public native;

    /// @notice Tokens to deposit during _addLiquidity()
    address[] public depositTokens;

    /// @notice Timestamp of the last harvest
    uint256 public lastHarvest;

    /// @notice Total harvested amount not yet vested 
    uint256 public totalLocked;

    /// @notice Linear vesting duration for harvested amounts
    uint256 public lockDuration;

    /// @notice Toggle harvests on deposits
    bool public harvestOnDeposit;

    /// @notice Reward tokens to compound
    address[] public rewards;

    /// @notice Minimum amounts of tokens to swap
    mapping(address => uint256) public minAmounts;

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

    /// @dev Initialize the Base Strategy
    /// @param _baseStrategyAddresses Struct of required addresses for the Base Strategy
    /// @param _commonAddresses Struct of required addresses for the Strategy Manager
    function __BaseStrategy_init(
        BaseStrategyAddresses calldata _baseStrategyAddresses,
        CommonAddresses calldata _commonAddresses
    ) internal onlyInitializing {
        __StratFeeManager_init(_commonAddresses);
        __StrategySwapper_init(_baseStrategyAddresses.beefySwapper);
        want = _baseStrategyAddresses.want;
        native = _baseStrategyAddresses.native;

        for (uint256 i; i < _baseStrategyAddresses.rewards.length; i++) {
            addReward(_baseStrategyAddresses.rewards[i]);
        }

        lockDuration = 6 hours;
        withdrawalFee = 0;
    }

    /// @notice Balance of want tokens in the underlying platform
    /// @dev Should be overridden in child
    function balanceOfPool() public view virtual returns (uint256);

    /// @notice Rewards available to be claimed by the strategy
    /// @dev Should be overridden in child
    function rewardsAvailable() external view virtual returns (uint256);

    /// @notice Call rewards in native token that the harvest caller could claim
    /// @dev Should be overridden in child
    function callReward() external view virtual returns (uint256);

    /// @dev Deposit want tokens to the underlying platform
    /// Should be overridden in child
    /// @param _amount Amount to deposit to the underlying platform
    function _deposit(uint256 _amount) internal virtual;

    /// @dev Withdraw want tokens from the underlying platform
    /// Should be overridden in child
    /// @param _amount Amount to withdraw from the underlying platform
    function _withdraw(uint256 _amount) internal virtual;

    /// @dev Withdraw all want tokens from the underlying platform
    /// Should be overridden in child
    function _emergencyWithdraw() internal virtual;

    /// @dev Claim reward tokens from the underlying platform
    /// Should be overridden in child
    function _claim() internal virtual;

    /// @dev Get the amounts of native that should be swapped to the corresponding depositTokens
    /// Should be overridden in child
    /// @return depositAmounts Amounts in native to swap
    function _getDepositAmounts() internal view virtual returns (uint256[] memory depositAmounts);

    /// @dev Add liquidity to the underlying platform using depositTokens to create the want token
    /// Should be overridden in child
    function _addLiquidity() internal virtual;

    /// @dev Revert if the reward token is one of the critical tokens used by the strategy
    /// Should be overridden in child
    function _verifyRewardToken(address _token) internal view virtual;

    /// @notice Deposit all want on this contract to the underlying platform
    function deposit() public whenNotPaused {
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
    function beforeDeposit() external override {
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
    function _harvest(address _callFeeRecipient, bool _onDeposit) internal whenNotPaused {
        uint256 wantBalanceBefore = balanceOfWant();
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));
        if (nativeBal > minAmounts[native]) {
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
            if (token == address(0)) {
                IWrappedNative(native).deposit{value: address(this).balance}();
            } else {
                uint256 amount = IERC20Upgradeable(token).balanceOf(address(this));
                if (amount > minAmounts[token]) {
                    IERC20Upgradeable(token).forceApprove(address(beefySwapper), amount);
                    _swap(token, native, amount);
                }
            }
        }
    }

    /// @dev Charge fees and send to recipients
    /// @param _callFeeRecipient Recipient for the harvest caller fees
    function _chargeFees(address _callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(_callFeeRecipient, callFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(strategist, strategistFeeAmount);

        uint256 beefyFeeAmount = nativeBal - callFeeAmount - strategistFeeAmount;
        IERC20Upgradeable(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    /// @dev Swap the remaining native to want tokens, either directly or by swapping to 
    /// depositTokens and adding liquidity
    function _swapNativeToWant() internal {
        uint256[] memory amounts = _getDepositAmounts();
        for (uint256 i; i < depositTokens.length; ++i) {
            if (depositTokens[i] != native && amounts[i] > 0) {
                IERC20Upgradeable(native).forceApprove(address(beefySwapper), amounts[i]);
                _swap(native, depositTokens[i], amounts[i]);
            }
        }
        _addLiquidity();
    }

    /// @notice Number of rewards that this strategy receives
    function rewardsLength() external view returns (uint256) {
        return rewards.length;
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

    /// @notice Set minimum amounts to be swapped for a token
    /// @param _token Token to have the minimum set for
    /// @param _minAmount Minimum amount that the token can be considered for swapping
    function setMinAmount(address _token, uint256 _minAmount) external onlyManager {
        minAmounts[_token] = _minAmount;
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

    /// @notice Vault can only call this when retiring a strategy. Sends all funds back to vault
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _emergencyWithdraw();
        IERC20Upgradeable(want).transfer(vault, balanceOfWant());
    }

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

    /// @dev Allow unwrapped native to be sent to this address
    receive () payable external {}
}