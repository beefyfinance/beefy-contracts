// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract BetuStaking is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 lastRewardBlock;  // Last block number that Rewards distribution occurs.
        uint256 accRewardTokenPerShare; // Accumulated Rewards per share, times 1e30. See below.
    }

    // The stake token
    IERC20 public STAKE_TOKEN;
    // The reward token
    IERC20 public REWARD_TOKEN;

    // Reward tokens created per block.
    uint256 public rewardPerBlock;

    // Keep track of number of tokens staked in case the contract earns reflect fees
    uint256 public totalStaked = 0;
    // Keep track of number of reward tokens paid to find remaining reward balance
    uint256 public totalRewardsPaid = 0;
    // Keep track of number of reward tokens allocated to find remaining reward balance
    uint256 public totalRewardsAllocated = 0;

    // Info of each pool.
    PoolInfo public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;
    // The block number when Reward mining starts.
    uint256 public startBlock;
	// The block number when mining ends.
    uint256 public bonusEndBlock;

    event Deposit(address indexed user, uint256 amount);
    event DepositRewards(uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 bonusEndBlock, uint256 rewardPerBlock);
    event EmergencyRewardWithdraw(address indexed user, uint256 amount);
    event EmergencySweepWithdraw(address indexed user, IERC20 indexed token, uint256 amount);

    constructor(
        IERC20 _stakeToken,
        IERC20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) public
    {
        STAKE_TOKEN = _stakeToken;
        REWARD_TOKEN = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // staking pool
        poolInfo = PoolInfo({
            lpToken: _stakeToken,
            lastRewardBlock: startBlock,
            accRewardTokenPerShare: 0
        });
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to - _from;
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock - _from;
        }
    }

    /// @param  _bonusEndBlock The block when rewards will end
    function setBonusEndBlock(uint256 _bonusEndBlock) external onlyOwner {
        require(_bonusEndBlock > block.number, 'new bonus end block must be greater than current');
        bonusEndBlock = _bonusEndBlock;
        emit LogUpdatePool(bonusEndBlock, rewardPerBlock);
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accRewardTokenPerShare = poolInfo.accRewardTokenPerShare;
        if (block.number > poolInfo.lastRewardBlock && totalStaked != 0) {
            uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier * rewardPerBlock;
            accRewardTokenPerShare = accRewardTokenPerShare + (tokenReward * 1e30 / totalStaked);
        }
        return user.amount * accRewardTokenPerShare / 1e30 - user.rewardDebt;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        if (block.number <= poolInfo.lastRewardBlock) {
            return;
        }
        if (totalStaked == 0) {
            poolInfo.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier * rewardPerBlock;
        totalRewardsAllocated += tokenReward;
        poolInfo.accRewardTokenPerShare = poolInfo.accRewardTokenPerShare + (tokenReward * 1e30 / totalStaked);
        poolInfo.lastRewardBlock = block.number;
    }


    /// Deposit staking token into the contract to earn rewards.
    /// @dev Since this contract needs to be supplied with rewards we are
    ///  sending the balance of the contract if the pending rewards are higher
    /// @param _amount The amount of staking tokens to deposit
    function deposit(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount * poolInfo.accRewardTokenPerShare / 1e30 - user.rewardDebt;
            if (pending > 0) {
                // If rewardBalance is low then revert to avoid losing the user's rewards
                require(rewardBalance() >= pending, "insufficient reward balance");
                safeTransferRewardInternal(address(msg.sender), pending);
            }
        }

        uint256 finalDepositAmount = 0;
        if (_amount > 0) {
            uint256 preStakeBalance = STAKE_TOKEN.balanceOf(address(this));
            poolInfo.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            finalDepositAmount = STAKE_TOKEN.balanceOf(address(this)) - preStakeBalance;
            user.amount = user.amount + finalDepositAmount;
            totalStaked = totalStaked + finalDepositAmount;
        }
        user.rewardDebt = user.amount * poolInfo.accRewardTokenPerShare / 1e30;

        emit Deposit(msg.sender, finalDepositAmount);
    }

    /// Withdraw rewards and/or staked tokens. Pass a 0 amount to withdraw only rewards
    /// @param _amount The amount of staking tokens to withdraw
    function withdraw(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending = user.amount * poolInfo.accRewardTokenPerShare / 1e30 - user.rewardDebt;
        if (pending > 0) {
            // If rewardBalance is low then revert to avoid losing the user's rewards
            require(rewardBalance() >= pending, "insufficient reward balance");
            safeTransferRewardInternal(address(msg.sender), pending);
        }

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            poolInfo.lpToken.safeTransfer(address(msg.sender), _amount);
            totalStaked = totalStaked - _amount;
        }

        user.rewardDebt = user.amount * poolInfo.accRewardTokenPerShare / 1e30;

        emit Withdraw(msg.sender, _amount);
    }

    /// Obtain the reward balance of this contract
    /// @return wei balance of contract
    function rewardBalance() public view returns (uint256) {
        uint256 balance = REWARD_TOKEN.balanceOf(address(this));
        if (STAKE_TOKEN == REWARD_TOKEN) {
            return balance - totalStaked;
        }
        return balance;
    }

    /// Get the balance of rewards that have not been harvested
    /// @return wei balance of rewards left to be paid
    function getUnharvestedRewards() public view returns (uint256) {
        return totalRewardsAllocated - totalRewardsPaid;
    }

    // Deposit Rewards into contract
    function depositRewards(uint256 _amount) external {
        require(_amount > 0, 'Deposit value must be greater than 0.');
        REWARD_TOKEN.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit DepositRewards(_amount);
    }

    /// @param _to address to send reward token to
    /// @param _amount value of reward token to transfer
    function safeTransferRewardInternal(address _to, uint256 _amount) internal {
        totalRewardsPaid += _amount;
        REWARD_TOKEN.safeTransfer(_to, _amount);
    }

    /* Admin Functions */

    /// @param _rewardPerBlock The amount of reward tokens to be given per block
    function setRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        rewardPerBlock = _rewardPerBlock;
        emit LogUpdatePool(bonusEndBlock, rewardPerBlock);
    }

    /* Emergency Functions */

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        poolInfo.lpToken.safeTransfer(address(msg.sender), user.amount);
        totalStaked = totalStaked - user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= rewardBalance(), 'not enough rewards');
        // Withdraw rewards
        REWARD_TOKEN.safeTransfer(msg.sender, _amount);
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    /// @notice A public function to sweep accidental BEP20 transfers to this contract.
    ///   Tokens are sent to owner
    /// @param token The address of the BEP20 token to sweep
    function sweepToken(IERC20 token) external onlyOwner {
        require(address(token) != address(STAKE_TOKEN), "can not sweep stake token");
        require(address(token) != address(REWARD_TOKEN), "can not sweep reward token");
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, balance);
        emit EmergencySweepWithdraw(msg.sender, token, balance);
    }

}
