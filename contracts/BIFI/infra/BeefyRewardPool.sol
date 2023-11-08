// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { SafeERC20Upgradeable, IERC20Upgradeable, IERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/// @title Reward pool for BIFI
/// @author kexley, Beefy
/// @notice Multi-reward staking contract for BIFI
/// @dev Multiple rewards can be added to this contract by the owner. A receipt token is issued for 
/// staking and is used for withdrawing the staked BIFI.
contract BeefyRewardPool is ERC20Upgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev Information for a particular reward
    /// @param periodFinish End timestamp of reward distribution
    /// @param duration Distribution length of time in seconds
    /// @param lastUpdateTime Latest timestamp of an update
    /// @param rate Distribution speed in wei per second
    /// @param rewardPerTokenStored Stored reward value per staked token in 18 decimals
    /// @param userRewardPerTokenPaid Stored reward value per staked token in 18 decimals at the 
    /// last time a user was paid the reward
    /// @param earned Value of reward still owed to the user
    struct RewardInfo {
        uint256 periodFinish;
        uint256 duration;
        uint256 lastUpdateTime;
        uint256 rate;
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) earned;
    }

    /// @notice BIFI token address
    IERC20Upgradeable public stakedToken;

    /// @notice Array of reward addresses
    address[] public rewards;

    /// @notice Whitelist of manager addresses
    mapping(address => bool) public whitelisted;

    /// @dev Limit to the number of rewards an owner can add
    uint256 private rewardMax;

    /// @dev Location of a reward in the reward array
    mapping(address => uint256) private _index;

    /// @dev Each reward address has a new unique identifier each time it is initialized. This is 
    /// to prevent old mappings from being reused when removing and re-adding a reward.
    mapping(address => bytes32) private _id;

    /// @dev Each identifier relates to reward information
    mapping(bytes32 => RewardInfo) private _rewardInfo;

    /// @notice User has staked an amount
    event Staked(address indexed user, uint256 amount);
    /// @notice User has withdrawn an amount
    event Withdrawn(address indexed user, uint256 amount);
    /// @notice A reward has been paid to the user
    event RewardPaid(address indexed user, address indexed reward, uint256 amount);
    /// @notice A new reward has been added to be distributed
    event AddReward(address reward);
    /// @notice More of an existing reward has been added to be distributed
    event NotifyReward(address indexed reward, uint256 amount, uint256 duration);
    /// @notice A reward has been removed from distribution and sent to the recipient
    event RemoveReward(address reward, address recipient);
    /// @notice The owner has removed tokens that are not supported by this contract
    event RescueTokens(address token, address recipient);
    /// @notice An address has been added to or removed from the whitelist
    event SetWhitelist(address manager, bool whitelist);

    /// @notice Caller is not a manager
    error NotManager(address caller);
    /// @notice The staked token cannot be added as a reward
    error StakedTokenIsNotAReward();
    /// @notice The duration is too short to be set
    error ShortDuration(uint256 duration);
    /// @notice There are already too many rewards
    error TooManyRewards();
    /// @notice The reward has not been found in the array
    error RewardNotFound(address reward);
    /// @notice The owner cannot withdraw the staked token
    error WithdrawingStakedToken();
    /// @notice the owner cannot withdraw an existing reward without first removing it from the array
    error WithdrawingRewardToken(address reward);

    /// @dev Triggers reward updates on every user interaction
    /// @param _user Address of the user making an interaction
    modifier update(address _user) {
        _update(_user);
        _;
    }

    /// @dev Only a manager can call these modified functions
    modifier onlyManager {
        if (!whitelisted[msg.sender]) revert NotManager(msg.sender);
        _;
    }

    /* ---------------------------------- EXTERNAL FUNCTIONS ---------------------------------- */

    /// @notice Initialize the contract, callable only once
    /// @param _stakedToken BIFI token address
    function initialize(address _stakedToken) external initializer {
        __ERC20_init("Beefy Reward Pool", "rBIFI");
        __Ownable_init();
        stakedToken = IERC20Upgradeable(_stakedToken);
        rewardMax = 100;
    }

    /// @notice Stake BIFI tokens
    /// @dev An equal number of receipt tokens will be minted to the caller
    /// @param _amount Amount of BIFI to stake
    function stake(uint256 _amount) external update(msg.sender) {
        _stake(msg.sender, _amount);
    }

    /// @notice Stake BIFI tokens with a permit
    /// @dev An equal number of receipt tokens will be minted to the caller
    /// @param _user User to stake for
    /// @param _amount Amount of BIFI to stake
    /// @param _deadline Timestamp of the deadline after which the permit is invalid
    /// @param _v Part of a signature
    /// @param _r Part of a signature
    /// @param _s Part of a signature
    function stakeWithPermit(
        address _user,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external update(_user) {
        IERC20PermitUpgradeable(address(stakedToken)).permit(
            _user, address(this), _amount, _deadline, _v, _r, _s
        );
        _stake(_user, _amount);
    }

    /// @notice Withdraw BIFI tokens
    /// @dev Burns an equal number of receipt tokens from the caller
    /// @param _amount Amount of BIFI to withdraw
    function withdraw(uint256 _amount) external update(msg.sender) {
        _withdraw(_amount);
    }

    /// @notice Withdraw all of the caller's BIFI tokens and claim rewards
    /// @dev Burns all receipt tokens owned by the caller
    function exit() external update(msg.sender) {
        _withdraw(balanceOf(msg.sender));
        _getReward();
    }

    /// @notice Claim all the caller's earned rewards 
    function getReward() external update(msg.sender) {
        _getReward();
    }

    /// @notice View the amount of rewards earned by the user
    /// @param _user User to view the earned rewards for
    /// @return rewardTokens Address array of the rewards
    /// @return earnedAmounts Amounts of the user's earned rewards
    function earned(address _user) external view returns (
        address[] memory rewardTokens,
        uint256[] memory earnedAmounts
    ) {
        uint256 rewardLength = rewards.length;
        uint256[] memory amounts = new uint256[](rewardLength);
        for (uint i; i < rewardLength;) {
            amounts[i] = _earned(_user, rewards[i]);
            unchecked { ++i; }
        }
        earnedAmounts = amounts;
        rewardTokens = rewards;
    }

    /// @notice View the amount of a single reward earned by the user
    /// @param _user User to view the earned reward for
    /// @param _reward Reward to calculate the earned amount for
    /// @return earnedAmount Amount of the user's earned reward
    function earned(address _user, address _reward) external view returns (uint256 earnedAmount) {
        earnedAmount = _earned(_user, _reward);
    }

    /// @notice View the reward information
    /// @dev The active reward information is automatically selected from the id mapping
    /// @param _rewardId Index of the reward in the array to get the information for
    /// @return reward Address of the reward
    /// @return periodFinish End timestamp of reward distribution
    /// @return duration Distribution length of time in seconds
    /// @return lastUpdateTime Latest timestamp of an update
    /// @return rate Distribution speed in wei per second
    function rewardInfo(uint256 _rewardId) external view returns (
        address reward,
        uint256 periodFinish,
        uint256 duration,
        uint256 lastUpdateTime,
        uint256 rate
    ) {
        reward = rewards[_rewardId];
        RewardInfo storage info = _getRewardInfo(reward);
        (periodFinish, duration, lastUpdateTime, rate) =
            (info.periodFinish, info.duration, info.lastUpdateTime, info.rate);
    }

    /* ------------------------------- ERC20 OVERRIDE FUNCTIONS ------------------------------- */

    /// @notice Update rewards for both source and recipient and then transfer receipt tokens to 
    /// the recipient address
    /// @dev Overrides the ERC20 implementation to add the reward update
    /// @param _to Recipient address of the token transfer
    /// @param _value Amount to transfer
    /// @return success Transfer was successful or not
    function transfer(address _to, uint256 _value) public override returns (bool success) {
        _update(msg.sender);
        _update(_to);
        return super.transfer(_to, _value);
    }

    /// @notice Update rewards for both source and recipient and then transfer receipt tokens from
    /// the source address to the recipient address
    /// @dev Overrides the ERC20 implementation to add the reward update
    /// @param _from Source address of the token transfer
    /// @param _to Recipient address of the token transfer
    /// @param _value Amount to transfer
    /// @return success Transfer was successful or not
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public override returns (bool success) {
        _update(_from);
        _update(_to);
        return super.transferFrom(_from, _to, _value);
    }

    /* ----------------------------------- OWNER FUNCTIONS ------------------------------------ */

    /// @notice Manager function to start a reward distribution
    /// @dev Must approve this contract to spend the reward amount before calling this function. 
    /// New rewards will be assigned a id using their address and the block timestamp.
    /// @param _reward Address of the reward
    /// @param _amount Amount of reward
    /// @param _duration Duration of the reward distribution in seconds
    function notifyRewardAmount(
        address _reward,
        uint256 _amount,
        uint256 _duration
    ) external onlyManager update(address(0)) {
        if (_reward == address(stakedToken)) revert StakedTokenIsNotAReward();
        if (_duration < 1 hours) revert ShortDuration(_duration);

        if (!_rewardExists(_reward)) {
            _id[_reward] = keccak256(abi.encodePacked(_reward, block.timestamp));
            uint256 rewardLength = rewards.length;
            if (rewards.length + 1 > rewardMax) revert TooManyRewards();
            _index[_reward] = rewardLength;
            rewards.push(_reward);
            emit AddReward(_reward);
        }

        IERC20Upgradeable(_reward).safeTransferFrom(msg.sender, address(this), _amount);

        RewardInfo storage rewardData = _getRewardInfo(_reward);
        uint256 leftover;

        if (block.timestamp < rewardData.periodFinish) {
            uint256 remaining = rewardData.periodFinish - block.timestamp;
            leftover = remaining * rewardData.rate;
        }

        rewardData.rate = (_amount + leftover) / _duration;
        rewardData.lastUpdateTime = block.timestamp;
        rewardData.periodFinish = block.timestamp + _duration;
        rewardData.duration = _duration;

        emit NotifyReward(_reward, _amount, _duration);
    }

    /// @notice Owner function to remove a reward from this contract
    /// @dev All unclaimed earnings are ignored. Re-adding the reward will have a new set of
    /// reward information so any unclaimed earnings cannot be recovered
    /// @param _reward Address of the reward to be removed
    /// @param _recipient Address of the recipient that the removed reward was sent to
    function removeReward(address _reward, address _recipient) external onlyOwner {
        if (!_rewardExists(_reward)) revert RewardNotFound(_reward);

        uint256 replacedIndex = _index[_reward];
        address endToken = rewards[rewards.length - 1];
        rewards[replacedIndex] = endToken;
        _index[endToken] = replacedIndex;
        rewards.pop();

        uint256 rewardBal = IERC20Upgradeable(_reward).balanceOf(address(this));
        IERC20Upgradeable(_reward).safeTransfer(_recipient, rewardBal);

        emit RemoveReward(_reward, _recipient);
    }

    /// @notice Owner function to remove unsupported tokens sent to this contract
    /// @param _token Address of the token to be removed
    /// @param _recipient Address of the recipient that the removed token was sent to
    function rescueTokens(address _token, address _recipient) external onlyOwner {
        if (_token == address(stakedToken)) revert WithdrawingStakedToken();
        if (_rewardExists(_token)) revert WithdrawingRewardToken(_token);

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(_recipient, amount);
        emit RescueTokens(_token, _recipient);
    }

    /// @notice Owner function to add addresses to the whitelist
    /// @param _manager Address able to call manager functions
    /// @param _whitelisted Whether to add or remove from whitelist
    function setWhitelist(address _manager, bool _whitelisted) external onlyOwner {
        whitelisted[_manager] = _whitelisted;
        emit SetWhitelist(_manager, _whitelisted);
    }

    /* ---------------------------------- INTERNAL FUNCTIONS ---------------------------------- */

    /// @dev Update the rewards and earnings for a user
    /// @param _user Address to update the earnings for
    function _update(address _user) private {
        uint256 rewardLength = rewards.length;
        for (uint i; i < rewardLength;) {
            address reward = rewards[i];
            RewardInfo storage rewardData = _getRewardInfo(reward);
            rewardData.rewardPerTokenStored = _rewardPerToken(reward);
            rewardData.lastUpdateTime = _lastTimeRewardApplicable(rewardData.periodFinish);
            if (_user != address(0)) {
                rewardData.earned[_user] = _earned(_user, reward);
                rewardData.userRewardPerTokenPaid[_user] = rewardData.rewardPerTokenStored;
            }
            unchecked { ++i; } 
        }
    }

    /// @dev Stake BIFI tokens and mint the caller receipt tokens
    /// @param _user Address of the user to stake for
    /// @param _amount Amount of BIFI to stake
    function _stake(address _user, uint256 _amount) private {
        _mint(_user, _amount);
        stakedToken.safeTransferFrom(_user, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    /// @dev Withdraw BIFI tokens and burn an equal number of receipt tokens from the caller
    /// @param _amount Amount of BIFI to withdraw
    function _withdraw(uint256 _amount) private {
        _burn(msg.sender, _amount);
        stakedToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    /// @dev Claim all the caller's earned rewards 
    function _getReward() private {
        uint256 rewardLength = rewards.length;
        for (uint i; i < rewardLength;) {
            address reward = rewards[i];
            uint256 rewardEarned = _earned(msg.sender, reward);
            if (rewardEarned > 0) {
                _getRewardInfo(reward).earned[msg.sender] = 0;
                _rewardTransfer(reward, msg.sender, rewardEarned);
                emit RewardPaid(msg.sender, reward, rewardEarned);
            }
            unchecked { ++i; }
        }
    }

    /// @dev Return either the period finish or the current timestamp, whichever is earliest
    /// @param _periodFinish End timestamp of the reward distribution
    /// @return timestamp Earliest timestamp out of the period finish or block timestamp 
    function _lastTimeRewardApplicable(uint256 _periodFinish) private view returns (uint256 timestamp) {
        timestamp = block.timestamp > _periodFinish ? _periodFinish : block.timestamp;
    }

    /// @dev Calculate the reward amount per BIFI token
    /// @param _reward Address of the reward
    /// @return rewardPerToken Reward amount per BIFI token
    function _rewardPerToken(address _reward) private view returns (uint256 rewardPerToken) {
        RewardInfo storage rewardData = _getRewardInfo(_reward);
        if (totalSupply() == 0) {
            rewardPerToken = rewardData.rewardPerTokenStored;
        } else {
            rewardPerToken = rewardData.rewardPerTokenStored + (
                (_lastTimeRewardApplicable(rewardData.periodFinish) - rewardData.lastUpdateTime) 
                * rewardData.rate
                * 1e18 
                / totalSupply()
            );
        }
    }

    /// @dev Calculate the reward amount earned by the user
    /// @param _user Address of the user
    /// @param _reward Address of the reward
    /// @return earnedAmount Amount of reward earned by the user
    function _earned(address _user, address _reward) private view returns (uint256 earnedAmount) {
        RewardInfo storage rewardData = _getRewardInfo(_reward);
        earnedAmount = rewardData.earned[_user] + (
            balanceOf(_user) * 
            (_rewardPerToken(_reward) - rewardData.userRewardPerTokenPaid[_user]) 
            / 1e18
        );
    }

    /// @dev Return the most current reward information for a reward
    /// @param _reward Address of the reward
    /// @return info Reward information for the reward
    function _getRewardInfo(address _reward) private view returns(RewardInfo storage info) {
        info = _rewardInfo[_id[_reward]];
    }

    /// @dev Check if a reward exists in the reward array already
    /// @param _reward Address of the reward
    /// @return exists Returns true if token is in the array
    function _rewardExists(address _reward) private view returns (bool exists) {
        if (rewards.length > 0) exists = _reward == rewards[_index[_reward]];
    }

    /// @dev Transfer at most the balance of the reward on this contract to avoid errors
    /// @param _reward Address of the reward
    /// @param _recipient Address of the recipient of the reward
    /// @param _amount Amount of the reward to be sent to the recipient
    function _rewardTransfer(address _reward, address _recipient, uint256 _amount) private {
        uint256 rewardBal = IERC20Upgradeable(_reward).balanceOf(address(this));
        if (_amount > rewardBal) _amount = rewardBal;
        if (_amount > 0) IERC20Upgradeable(_reward).safeTransfer(_recipient, _amount);
    }
}
