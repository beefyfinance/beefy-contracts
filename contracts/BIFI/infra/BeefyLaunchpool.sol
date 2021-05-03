pragma solidity ^0.5.0;

import "@openzeppelin-2/contracts/math/Math.sol";
import "@openzeppelin-2/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-2/contracts/ownership/Ownable.sol";

import "../utils/LPTokenWrapper.sol";

contract BeefyLaunchpool is LPTokenWrapper, Ownable {
    IERC20 public rewardToken;
    uint256 public duration;
    uint256 public capPerAddr;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _stakedToken, address _rewardToken,  uint256 _duration, uint256 _capPerAddr)
        public
        LPTokenWrapper(_stakedToken)
    {
        rewardToken = IERC20(_rewardToken);
        duration = _duration;
        capPerAddr = _capPerAddr;
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
        require(balanceOf(msg.sender).add(amount) <= capPerAddr, "Cap reached");
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

    function notifyRewardAmount()
        external
        onlyOwner
        updateReward(address(0))
    {
        uint256 reward = IERC20(rewardToken).balanceOf(address(this));
        if (periodFinish == 0) {
            if (block.timestamp >= periodFinish) {
                rewardRate = reward.div(duration);
            } else {
                uint256 remaining = periodFinish.sub(block.timestamp);
                uint256 leftover = remaining.mul(rewardRate);
                rewardRate = reward.add(leftover).div(duration);
            }
            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp.add(duration);
            emit RewardAdded(reward);
        }
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        if (periodFinish != 0) {
            require(_token != address(stakedToken), "!staked");
            require(_token != address(rewardToken), "!reward");
        }
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
