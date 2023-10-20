// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { SafeERC20Upgradeable, IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IBeefySwapper } from "../../interfaces/beefy/IBeefySwapper.sol";
import { IBeefyRewardPool } from "../../interfaces/beefy/IBeefyRewardPool.sol";
import { StratFeeManagerInitializable, IFeeConfig } from "../Common/StratFeeManagerInitializable.sol";

/// @title Strategy staking in the BIFI reward pool
/// @author kexley, Beefy
/// @notice Strategy managing the rewards from the BIFI reward pool
contract StrategyBeefy is StratFeeManagerInitializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice BIFI token address
    address public want;

    /// @notice WETH token address
    address public native;

    /// @notice Reward token array
    address[] public rewards;

    /// @dev Location of a reward in the token array
    mapping(address => uint256) index;

    /// @notice Reward pool for BIFI rewards
    address public rewardPool;

    /// @notice Whether to harvest on deposits
    bool public harvestOnDeposit;

    /// @notice Timestamp of last harvest
    uint256 public lastHarvest;
    
    /// @notice Total profit locked on the strategy
    uint256 public totalLocked;

    /// @notice Length of time in seconds to linearly unlock the profit from a harvest
    uint256 public duration;

    /// @dev Reward entered is a protected token
    error RewardNotAllowed(address reward);
    /// @dev Reward is already in the array
    error RewardAlreadySet(address reward);
    /// @dev Reward is not found in the array
    error RewardNotFound(address reward);

    /// @notice Strategy has been harvested
    /// @param harvester Caller of the harvest
    /// @param wantHarvested Amount of want harvested in this tx
    /// @param tvl Total amount of deposits at the time of harvest
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    /// @notice Want tokens have been deposited into the underlying platform
    /// @param tvl Total amount of deposits at the time of deposit 
    event Deposit(uint256 tvl);
    /// @notice Want tokens have been withdrawn by a user
    /// @param tvl Total amount of deposits at the time of withdrawal
    event Withdraw(uint256 tvl);
    /// @notice Fees were charged
    /// @param callFees Amount of native sent to the caller as a harvest reward
    /// @param beefyFees Amount of native sent to the beefy fee recipient
    /// @param strategistFees Amount of native sent to the strategist
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);
    /// @notice Duration of the locked profit degradation has been set
    /// @param duration Duration of the locked profit degradation
    event SetDuration(uint256 duration);
    /// @notice A new reward has been added to the array
    /// @param reward New reward
    event SetReward(address reward);
    /// @notice A reward has been removed from the array
    /// @param reward Reward that has been removed
    event RemoveReward(address reward);

    /// @notice Initialize the contract, callable only once
    /// @param _want BIFI address
    /// @param _native WETH address
    /// @param _rewardPool Reward pool address
    /// @param _commonAddresses The typical addresses required by a strategy (see StratManager)
    function initialize(
        address _want,
        address _native,
        address _rewardPool,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        native = _native;
        rewardPool = _rewardPool;
        duration = 3 days;

        _giveAllowances();
    }

    /// @notice Deposit all available want on this contract into the underlying platform
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

        if (wantBal > 0) {
            IBeefyRewardPool(rewardPool).stake(wantBal);
            emit Deposit(balanceOf());
        }
    }

    /// @notice Withdraw some amount of want back to the vault
    /// @param _amount Some amount to withdraw back to vault
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IBeefyRewardPool(rewardPool).withdraw(_amount - wantBal);
            wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20Upgradeable(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    /// @notice Hook called by the vault before shares are calculated on a deposit
    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    /// @notice Harvest rewards and collect a call fee reward
    function harvest() external {
        _harvest(tx.origin);
    }

    /// @notice Harvest rewards and send the call fee reward to a specified recipient
    /// @param _callFeeRecipient Recipient of the call fee reward
    function harvest(address _callFeeRecipient) external {
        _harvest(_callFeeRecipient);
    }

    /// @dev Harvest rewards, charge fees and compound back into more want
    /// @param _callFeeRecipient Recipient of the call fee reward 
    function _harvest(address _callFeeRecipient) internal whenNotPaused {
        IBeefyRewardPool(rewardPool).getReward();
        _swapToNative();
        if (IERC20Upgradeable(native).balanceOf(address(this)) > 0) {
            _chargeFees(_callFeeRecipient);
            _swapToWant();
            uint256 wantHarvested = balanceOfWant();
            totalLocked = wantHarvested + lockedProfit();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    /// @dev Swap any extra rewards into native
    function _swapToNative() internal {
        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            uint256 rewardBal = IERC20Upgradeable(reward).balanceOf(address(this));
            if (rewardBal > 0) IBeefySwapper(unirouter).swap(reward, native, rewardBal);
        }
    }

    /// @dev Charge performance fees and send to recipients
    /// @param _callFeeRecipient Recipient of the call fee reward 
    function _chargeFees(address _callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(_callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    /// @dev Swap all native into want
    function _swapToWant() internal {
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));
        if (nativeBal > 0) IBeefySwapper(unirouter).swap(native, want, nativeBal);
    }

    /// @notice Total want controlled by the strategy in the underlying platform and this contract
    /// @return balance Total want controlled by the strategy 
    function balanceOf() public view returns (uint256 balance) {
        balance = balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    /// @notice Amount of want held on this contract
    /// @return balanceHeld Amount of want held
    function balanceOfWant() public view returns (uint256 balanceHeld) {
        balanceHeld = IERC20Upgradeable(want).balanceOf(address(this));
    }

    /// @notice Amount of want controlled by the strategy in the underlying platform
    /// @return balanceInvested Amount of want in the underlying platform
    function balanceOfPool() public view returns (uint256 balanceInvested) {
        balanceInvested = IERC20Upgradeable(rewardPool).balanceOf(address(this));
    }

    /// @notice Amount of locked profit degrading over time
    /// @return left Amount of locked profit still remaining
    function lockedProfit() public view returns (uint256 left) {
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < duration ? duration - elapsed : 0;
        left = totalLocked * remaining / duration;
    }

    /// @notice Unclaimed reward amount from the underlying platform
    /// @return unclaimedReward Amount of reward left unclaimed
    function rewardsAvailable() public view returns (uint256 unclaimedReward) {
        unclaimedReward = IBeefyRewardPool(rewardPool).earned(address(this), native);
    }

    /// @notice Estimated call fee reward for calling harvest
    /// @return callFee Amount of native reward a harvest caller could claim
    function callReward() public view returns (uint256 callFee) {
        IFeeConfig.FeeCategory memory fees = getFees();
        callFee = rewardsAvailable() * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    /// @notice Manager function to toggle on harvesting on deposits
    /// @param _harvestOnDeposit Turn harvesting on deposit on or off
    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    /// @notice Called by the vault as part of strategy migration, all funds are sent to the vault
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IBeefyRewardPool(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).transfer(vault, wantBal);
    }

    /// @notice Pauses deposits and withdraws all funds from the underlying platform
    function panic() public onlyManager {
        pause();
        IBeefyRewardPool(rewardPool).withdraw(balanceOfPool());
    }

    /// @notice Pauses deposits but leaves funds still invested
    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    /// @notice Unpauses deposits and reinvests any idle funds
    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    /// @notice Set the duration for the degradation of the locked profit
    /// @param _duration Duration for the degradation of the locked profit
    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
        emit SetDuration(_duration);
    }

    /// @notice Add a new reward to the array
    /// @param _reward New reward
    function setReward(address _reward) external onlyOwner {
        if (_reward == want || _reward == native || _reward == rewardPool) {
            revert RewardNotAllowed(_reward);
        }
        if (rewards.length > 0) {
            if (_reward == rewards[index[_reward]]) revert RewardAlreadySet(_reward);
        }
        index[_reward] = rewards.length;
        rewards.push(_reward);
        IERC20Upgradeable(_reward).forceApprove(unirouter, type(uint).max);
        emit SetReward(_reward);
    }

    /// @notice Remove a reward from the array
    /// @param _reward Removed reward
    function removeReward(address _reward) external onlyManager {
        if (_reward != rewards[index[_reward]]) revert RewardNotFound(_reward);
        address endReward = rewards[rewards.length - 1];
        uint256 replacedIndex = index[_reward];
        index[endReward] = replacedIndex;
        rewards[replacedIndex] = endReward;
        rewards.pop();
        IERC20Upgradeable(_reward).forceApprove(unirouter, 0);
        emit RemoveReward(_reward);
    }

    /// @dev Give out allowances to third party contracts
    function _giveAllowances() internal {
        IERC20Upgradeable(want).forceApprove(rewardPool, type(uint).max);
        IERC20Upgradeable(native).forceApprove(unirouter, type(uint).max);
        for (uint i; i < rewards.length; ++i) {
            IERC20Upgradeable(rewards[i]).forceApprove(unirouter, type(uint).max);
        }
    }

    /// @dev Revoke allowances from third party contracts
    function _removeAllowances() internal {
        IERC20Upgradeable(want).forceApprove(rewardPool, 0);
        IERC20Upgradeable(native).forceApprove(unirouter, 0);
        for (uint i; i < rewards.length; ++i) {
            IERC20Upgradeable(rewards[i]).forceApprove(unirouter, 0);
        }
    }
}
