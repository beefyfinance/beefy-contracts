// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-4/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../utils/LPTokenWrapperInitializable.sol";

contract BeefyBoost is LPTokenWrapperInitializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    uint256 public duration;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    uint256 public rewardBalance;

    address public manager;
    address public treasury;
    uint256 public treasuryFee;

    bool public isPreStake;

    mapping(address => bool) public notifiers;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    function initialize(
        address _stakedToken,
        address _rewardToken,
        uint256 _duration,
        address _manager,
        address _treasury
    ) public initializer {
        __LPTokenWrapper_init(_stakedToken);
        __Ownable_init();
        rewardToken = IERC20(_rewardToken);
        duration = _duration;
        manager = _manager;
        treasury = _treasury;
        treasuryFee = 500;
    }

    modifier onlyManager() {
        require(msg.sender == manager || msg.sender == owner(), "!manager");
        _;
    }

    modifier onlyNotifier() {
        require(msg.sender == manager || msg.sender == owner() || notifiers[msg.sender], "!notifier");
        _;
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
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalSupply());
    }

    function earned(address account) public view returns (uint256) {
        return balanceOf(account) * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + rewards[account];
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) public override updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override updateReward(msg.sender) {
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
            rewardBalance -= reward;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function setRewardDuration(uint256 _duration) external onlyManager {
        require(block.timestamp >= periodFinish);
        duration = _duration;
    }

    function setTreasuryFee(uint256 _fee) external onlyManager {
        require(_fee <= 500);
        treasuryFee = _fee;
    }

    function setTreasury(address _treasury) external onlyManager {
        treasury = _treasury;
    }

    function openPreStake() external onlyManager {
        isPreStake = true;
    }

    function closePreStake() external onlyManager {
        isPreStake = false;
    }

    function setNotifier(address _notifier, bool _enable) external onlyManager {
        notifiers[_notifier] = _enable;
    }

    function _notify(uint256 reward) internal updateReward(address(0)) {
        uint256 fee = reward * treasuryFee / 10000;
        if (fee > 0) {
            rewardToken.safeTransfer(treasury, fee);
            reward -= fee;
        }
        require(reward != 0, "no rewards");
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / duration;
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        rewardBalance += reward;
        isPreStake = false;
        emit RewardAdded(reward);
    }

    function notifyAmount(uint256 _amount) external onlyNotifier {
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        _notify(_amount);
    }

    function notifyAlreadySent() external onlyNotifier {
        uint256 balance = rewardToken.balanceOf(address(this));
        uint256 userRewards = rewardBalance;
        if (rewardToken == stakedToken) {
            userRewards = userRewards + totalSupply();
        }
        uint256 newRewards = balance - userRewards;
        _notify(newRewards);
    }

    function inCaseTokensGetStuck(address _token) external onlyManager {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        inCaseTokensGetStuck(_token, msg.sender, amount);
    }

    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyManager {
        if (totalSupply() != 0) {
            require(_token != address(stakedToken), "!staked");
        }
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
