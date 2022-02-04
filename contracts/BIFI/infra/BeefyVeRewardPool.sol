// SPDX-License-Identifier: MIT

pragma solidity ^0.5.0;

import "@openzeppelin-2/contracts/math/Math.sol";
import "@openzeppelin-2/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-2/contracts/ownership/Ownable.sol";

import "../utils/LPTokenWrapper.sol";

interface IGaugeStaker {
    function claimVeWantReward() external;
}

contract BeefyVeRewardPool is LPTokenWrapper, Ownable {
    IERC20 public rewardToken;
    uint256 public constant DURATION = 7 days;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    bool public notifyOnDeposit;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    address public gaugeStaker;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _stakedToken, address _rewardToken, address _gaugeStaker)
        public
        LPTokenWrapper(_stakedToken)
    {
        rewardToken = IERC20(_rewardToken);
        gaugeStaker = _gaugeStaker;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        if (notifyOnDeposit) {
            claimAndNotify();
        }
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function claimAndNotify() public {
        uint256 beforeBal = IERC20(rewardToken).balanceOf(address(this));
        IGaugeStaker(gaugeStaker).claimVeWantReward();
        uint256 claimedBal = IERC20(rewardToken).balanceOf(address(this)).sub(beforeBal);
        if (claimedBal > 0) {
            _notifyRewardAmount(claimedBal);
        }
    }

    function notifyRewardAmount(uint256 reward) external onlyOwner {
        _notifyRewardAmount(reward);
    }

    function _notifyRewardAmount(uint256 reward)
        internal
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(DURATION);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(DURATION);
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(DURATION);
        emit RewardAdded(reward);
    }

    function setNotifyOnDeposit(bool _notifyOnDeposit) external onlyOwner {
        notifyOnDeposit = _notifyOnDeposit;
    }

    function setGaugeStaker(address _gaugeStaker) external onlyOwner {
        gaugeStaker = _gaugeStaker;
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(stakedToken), "!staked");
        require(_token != address(rewardToken), "!reward");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
