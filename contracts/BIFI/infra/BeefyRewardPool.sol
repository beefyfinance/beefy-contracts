// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../utils/LPTokenWrapperInitializable.sol";

contract BeefyRewardPool is LPTokenWrapperInitializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct RewardInfo {
        uint256 periodFinish;
        uint256 duration;
        uint256 lastUpdateTime;
        uint256 rewardRate;
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewardsEarned;
    }

    mapping(address => RewardInfo) public rewardInfo;
    address[] public rewardTokens;
    mapping(address => uint256) public rewardTokenIndex;
    uint256 public rewardMax;

    event RewardAdded(address indexed reward, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed reward, uint256 amount);

    error EmptyStake();
    error EmptyWithdraw();
    error StakedTokenIsNotAReward();
    error ShortDuration();
    error TooManyRewards();
    error OverNotify();
    error RewardNotFound();
    error WithdrawingStakedToken();
    error WithdrawingRewardToken();

    function initialize(address _stakedToken) external initializer {
        __LPTokenWrapper_init(_stakedToken);
        __Ownable_init();
        rewardMax = 10;
    }

    modifier updateReward(address _account) {
        for (uint i; i < rewardTokens.length; ++i) {
            address reward = rewardTokens[i];
            rewardInfo[reward].rewardPerTokenStored = rewardPerToken(reward);
            rewardInfo[reward].lastUpdateTime = lastTimeRewardApplicable(reward);
            if (_account != address(0)) {
                rewardInfo[reward].rewardsEarned[_account] = earned(_account, reward);
                rewardInfo[reward].userRewardPerTokenPaid[_account] = 
                    rewardInfo[reward].rewardPerTokenStored;
            }
        }
        _;
    }

    function lastTimeRewardApplicable(address _reward) public view returns (uint256) {
        return 
            block.timestamp > rewardInfo[_reward].periodFinish 
                ? rewardInfo[_reward].periodFinish
                : block.timestamp;
    }

    function rewardPerToken(address _reward) public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardInfo[_reward].rewardPerTokenStored;
        }
        return
            rewardInfo[_reward].rewardPerTokenStored + (
                (lastTimeRewardApplicable(_reward) - rewardInfo[_reward].lastUpdateTime) 
                * rewardInfo[_reward].rewardRate
                * 1e18 
                / totalSupply()
            );
    }

    function earned(address _account, address _reward) public view returns (uint256) {
        return
            rewardInfo[_reward].rewardsEarned[_account] + (
                balanceOf(_account) * 
                (rewardPerToken(_reward) - rewardInfo[_reward].userRewardPerTokenPaid[_account]) 
                / 1e18
            );
    }

    function stake(uint256 _amount) public override updateReward(msg.sender) {
        if (_amount == 0) revert EmptyStake();
        super.stake(_amount);
        emit Staked(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) public override updateReward(msg.sender) {
        if (_amount == 0) revert EmptyWithdraw();
        super.withdraw(_amount);
        emit Withdrawn(msg.sender, _amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) {
        for (uint i; i < rewardTokens.length; ++i) {
            address reward = rewardTokens[i];
            uint256 rewardEarned = earned(msg.sender, reward);
            if (rewardEarned > 0) {
                rewardInfo[reward].rewardsEarned[msg.sender] = 0;
                _safeRewardTransfer(reward, msg.sender, rewardEarned);
                emit RewardPaid(msg.sender, reward, rewardEarned);
            }
        }
    }

    function getReward(address _reward) external updateReward(msg.sender) {
        uint256 rewardEarned = earned(msg.sender, _reward);
        if (rewardEarned > 0) {
            rewardInfo[_reward].rewardsEarned[msg.sender] = 0;
            _safeRewardTransfer(_reward, msg.sender, rewardEarned);
            emit RewardPaid(msg.sender, _reward, rewardEarned);
        }
    }

    function notifyRewardAmount(
        address _reward,
        uint256 _amount,
        uint256 _duration
    ) external onlyOwner updateReward(address(0)) {
        if (_reward == address(stakedToken)) revert StakedTokenIsNotAReward();
        if (_duration < 1 days) revert ShortDuration();
        if (_reward != rewardTokens[rewardTokenIndex[_reward]]) {
            if (rewardTokens.length > rewardMax - 1) revert TooManyRewards();
            rewardTokenIndex[_reward] = rewardTokens.length;
            rewardTokens.push(_reward);
        }

        uint256 leftover;
        if (block.timestamp < rewardInfo[_reward].periodFinish) {
            uint256 remaining = rewardInfo[_reward].periodFinish - block.timestamp;
            leftover = remaining * rewardInfo[_reward].rewardRate;
        }
        if (_amount + leftover > IERC20Upgradeable(_reward).balanceOf(address(this))) revert OverNotify();
        rewardInfo[_reward].rewardRate = (_amount + leftover) / _duration;
        rewardInfo[_reward].lastUpdateTime = block.timestamp;
        rewardInfo[_reward].periodFinish = block.timestamp + _duration;
        rewardInfo[_reward].duration = _duration;
        emit RewardAdded(_reward, _amount);
    }

    function removeReward(address _reward) external onlyOwner updateReward(address(0)) {
        if (_reward != rewardTokens[rewardTokenIndex[_reward]]) revert RewardNotFound();
        if (block.timestamp < rewardInfo[_reward].periodFinish) {
            uint256 remaining = rewardInfo[_reward].periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardInfo[_reward].rewardRate;
            if (leftover > 0) IERC20Upgradeable(_reward).safeTransfer(owner(), leftover);
            rewardInfo[_reward].periodFinish = block.timestamp;
        }
        address endToken = rewardTokens[rewardTokens.length - 1];
        rewardTokenIndex[endToken] = rewardTokenIndex[_reward];
        rewardTokens[rewardTokenIndex[_reward]] = endToken;
        rewardTokens.pop();
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        if (_token == address(stakedToken)) revert WithdrawingStakedToken();
        if (_token == rewardTokens[rewardTokenIndex[_token]]) revert WithdrawingRewardToken();

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(owner(), amount);
    }

    function _safeRewardTransfer(address _reward, address _recipient, uint256 _amount) internal {
        uint256 rewardBal = IERC20Upgradeable(_reward).balanceOf(address(this));
        if (_amount > rewardBal) {
            _amount = rewardBal;
        }
        if (_amount > 0) {
            IERC20Upgradeable(_reward).safeTransfer(_recipient, _amount);
        }
    }
}
