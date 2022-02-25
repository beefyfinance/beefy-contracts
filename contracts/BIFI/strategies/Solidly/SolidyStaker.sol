// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IVoter {
    function _ve() external view returns (address);
    function gauges(address) external view returns (address);
    function bribes(address) external view returns (address);
    function minter() external view returns (address);
    function length() external view returns(uint256);
    function pools(uint) external view returns (address);
    function vote(uint tokenId, address[] calldata _poolVote, int256[] calldata _weights) external;
    function reset(uint _tokenId) external;
    function whitelist(address _token, uint _tokenId) external;
    function createGauge(address _pool) external returns (address);
}

interface IVeToken {
    function token() external view returns (address);
    function ownerOf(uint) external view returns (address);
    function create_lock(uint _value, uint _lock_duration) external returns (uint);
    function withdraw(uint _tokenId) external;
    function increase_amount(uint _tokenId, uint _value) external;
    function increase_unlock_time(uint _tokenId, uint _lock_duration) external;
    function merge(uint _from, uint _to) external;
    function locked(uint) external view returns (uint256, uint256);
    function safeTransferFrom(address from, address to, uint tokenId) external;
}

interface IGauge {
    function bribe() external view returns (address);
    function isReward(address) external view returns (bool);
    function getReward(address account, address[] memory tokens) external;
    function earned(address token, address account) external view returns (uint);
    function stake() external view returns (address);
    function deposit(uint amount, uint tokenId) external;
    function withdraw(uint amount) external;
    function withdrawToken(uint amount, uint tokenId) external;
    function tokenIds(address owner) external view returns (uint256 tokenId);
}

interface IBribe {
    function isReward(address) external view returns (bool);
    function getReward(uint tokenId, address[] memory tokens) external;
    function earned(address token, uint tokenId) external view returns (uint);
}

interface IVeDist {
    function claim(uint tokenId) external returns (uint);
}

interface IMinter{
    function _ve_dist() external view returns (address);
}

// SolidlyStaker
contract SolidlyStaker is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        mapping(address => uint256) rewardDebt; // Reward debt for each reward token.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // LP address
        address gauge; // Gauge address
        address bribe; // Bribe address
        uint256 totalDepositedAmount; // # of deposit tokens in this pool
        uint256 lastRewardTime; // Last block time that reward distribution occurred.
        mapping(address => uint256) accRewardPerShare; // Accumulated reward per share, times 1e18.
        address[] rewards; // Reward tokens for the pool.
    }

    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Stored balance of rewards.
    mapping(address => uint256) public storedRewardBalance;
    // Existing pools to check for duplicates.
    mapping(address => bool) public isExistingPool;

    IVoter public voter;
    IVeToken public veToken;
    IVeDist public veDist;
    uint256 public veTokenId;
    IERC20 public baseToken;
    address public keeper;
    address public treasury;

    event Deposit(address indexed user, uint256 pid, uint256 amount);
    event Withdraw(address indexed user, uint256 pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 pid, uint256 amount);

    event CreateLock(address indexed user, uint256 veTokenId, uint256 amount, uint256 unlockTime);
    event Release(address indexed user, uint256 veTokenId, uint256 amount);
    event IncreaseTime(address indexed user, uint256 veTokenId, uint256 unlockTime);
    event ClaimVeEmissions(address indexed user, uint256 veTokenId, uint256 amount);
    event ClaimOwnerRewards(address indexed user, uint256[] pids, address[][] tokens);
    event IncreaseAmount(address indexed user, uint256 veTokenId, uint256 amount);
    event TransferVeToken(address indexed user, address to, uint256 veTokenId);

    constructor(address _voter) public {
        voter = IVoter(_voter);
        veToken = IVeToken(voter._ve());
        baseToken = IERC20(veToken.token());
        IMinter _minter = IMinter(voter.minter());
        veDist = IVeDist(_minter._ve_dist());

        baseToken.safeApprove(address(veToken), uint256(-1));
    }

    function setVeTokenId(uint256 _veTokenId) external onlyManager {
        require(_veTokenId == 0 || veToken.ownerOf(_veTokenId) == address(this), "!veTokenId");
        veTokenId = _veTokenId;
    }

    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setVeDist(address _veDist) external onlyOwner {
        veDist = IVeDist(_veDist);
    }

    // Add a new lp to the pool. Can only be called by the manager.
    function add(address _poolToken, address[] memory _rewards) public onlyManager {
        require(isExistingPool[_poolToken] == false, "pool already exists");
        address _gauge = voter.gauges(_poolToken);
        if (_gauge == address(0)) {
            _gauge = voter.createGauge(_poolToken);
        }
        poolInfo.push(PoolInfo({
            lpToken: IERC20(_poolToken),
            gauge: _gauge,
            bribe: voter.bribes(_gauge),
            totalDepositedAmount: 0,
            lastRewardTime: block.timestamp,
            rewards: _rewards
        }));
        IERC20(_poolToken).safeApprove(address(_gauge), uint256(-1));
        isExistingPool[_poolToken] == true;
    }

    // Set rewards for the pool.
    function set(uint256 _pid, address[] memory _rewards) public onlyManager {
        poolInfo[_pid].rewards = _rewards;
    }

    // View function to see pending reward.
    function pendingReward(address _user, uint256 _pid) external view returns (address[] memory, uint256[] memory)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        address[] memory _rewards = pool.rewards;
        uint256[] memory _amounts;

        for (uint256 i; i < _rewards.length; i++) {
            uint256 _rewardBal = IGauge(pool.gauge).earned(_rewards[i], address(this));
            if (_rewardBal > 0) {
                uint256 _accRewardPerShare = pool.accRewardPerShare[_rewards[i]];
                _accRewardPerShare = _accRewardPerShare.add((_rewardBal.mul(1e18).div(pool.totalDepositedAmount)));
                _amounts[i] = user.amount
                    .mul(_accRewardPerShare)
                    .div(1e18)
                    .sub(user.rewardDebt[_rewards[i]]);
            }
        }
        return (_rewards, _amounts);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        if (pool.totalDepositedAmount == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        IGauge(pool.gauge).getReward(address(this), pool.rewards);
        for (uint256 i; i < pool.rewards.length; i++) {
            address _reward = pool.rewards[i];
            uint256 _rewardBal = IERC20(_reward).balanceOf(address(this)).sub(storedRewardBalance[_reward]);
            pool.accRewardPerShare[_reward] = pool.accRewardPerShare[_reward]
                .add((_rewardBal.mul(1e18).div(pool.totalDepositedAmount)));
            storedRewardBalance[_reward] = storedRewardBalance[_reward].add(_rewardBal);
        }

        pool.lastRewardTime = block.timestamp;
    }

    // Deposit tokens.
    function deposit(uint256 _pid, uint256 _amount) external whenNotPaused {
        require(veTokenId > 0, "!veTokenId");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            for (uint256 i; i < pool.rewards.length; i++) {
                address _reward = pool.rewards[i];
                uint256 pending = user.amount
                    .mul(pool.accRewardPerShare[_reward])
                    .div(1e18)
                    .sub(user.rewardDebt[_reward]);
                if (pending > 0) {
                    safeTransfer(IERC20(_reward), msg.sender, pending);
                    storedRewardBalance[_reward] = storedRewardBalance[_reward] > pending
                        ? storedRewardBalance[_reward].sub(pending)
                        : 0;
                }
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalDepositedAmount = pool.totalDepositedAmount.add(_amount);
            IGauge(pool.gauge).deposit(_amount, veTokenId);
        }
        for (uint256 i; i < pool.rewards.length; i++) {
            address _reward = pool.rewards[i];
            user.rewardDebt[_reward] = user.amount.mul(pool.accRewardPerShare[_reward]).div(1e18);
        }
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw tokens.
    function withdraw(uint256 _pid, uint256 _amount) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw not good");
        updatePool(_pid);
        for (uint256 i; i < pool.rewards.length; i++) {
            address _reward = pool.rewards[i];
            uint256 pending = user.amount.mul(pool.accRewardPerShare[_reward]).div(1e18).sub(user.rewardDebt[_reward]);
            if (pending > 0) {
                safeTransfer(IERC20(_reward), msg.sender, pending);
                storedRewardBalance[_reward] = storedRewardBalance[_reward] > pending
                    ? storedRewardBalance[_reward].sub(pending)
                    : 0;
            }
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalDepositedAmount = pool.totalDepositedAmount.sub(_amount);
            IGauge(pool.gauge).withdraw(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        for (uint256 i; i < pool.rewards.length; i++) {
            address _reward = pool.rewards[i];
            user.rewardDebt[_reward] = user.amount.mul(pool.accRewardPerShare[_reward]).div(1e18);
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        IGauge(pool.gauge).withdraw(user.amount);
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        pool.totalDepositedAmount = pool.totalDepositedAmount.sub(user.amount);
        user.amount = 0;
        for (uint256 i; i < pool.rewards.length; i++) {
            address _reward = pool.rewards[i];
            user.rewardDebt[_reward] = 0;
        }
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    }

    // claim veToken emissions and increases locked amount in veToken
    function claimVeEmissions() external {
        uint256 _amount = veDist.claim(veTokenId);
        emit ClaimVeEmissions(msg.sender, veTokenId, _amount);
    }

    // claim owner rewards such as trading fees and bribes from gauges, transferred to treasury
    function claimOwnerRewards(uint256[] memory _pids, address[][] memory _tokens) external onlyManager nonReentrant {
        for (uint256 i; i < _pids.length; i++) {
            PoolInfo memory pool = poolInfo[_pids[i]];
            IBribe(pool.bribe).getReward(veTokenId, _tokens[i]);
            for (uint256 j; j < _tokens[i].length; j++) {
                address _reward = _tokens[i][j];
                uint256 rewardBal = IERC20(_reward).balanceOf(address(this)).sub(storedRewardBalance[_reward]);
                if (rewardBal > 0) {
                    IERC20(_reward).safeTransfer(treasury, rewardBal);
                }
            }
        }
        emit ClaimOwnerRewards(msg.sender, _pids, _tokens);
    }

    // create a new veToken if none is assigned to this address
    function createLock(uint256 _amount, uint256 _lock_duration) external onlyManager {
        require(veTokenId == 0, "veToken > 0");
        require(_amount > 0, "amount == 0");
        baseToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        veTokenId = veToken.create_lock(_amount, _lock_duration);
        emit CreateLock(msg.sender, veTokenId, _amount, _lock_duration);
    }

    // release expired lock of a non-main veToken owned by this address and transfer base token to treasury
    function release(uint256 _veTokenId) external onlyManager {
        require(_veTokenId > 0 && veTokenId != _veTokenId, "!veTokenId");
        veToken.withdraw(_veTokenId);
        uint256 _baseBal = baseToken.balanceOf(address(this)).sub(storedRewardBalance[address(baseToken)]);
        safeTransfer(baseToken, treasury, _baseBal);
        emit Release(msg.sender, _veTokenId, _baseBal);
    }

    // merge voting power of two veTokens by burning the _from veToken, _from must be detached and not voted with
    function merge(uint256 _fromId, uint256 _toId) external onlyManager {
        require(_fromId != veTokenId, "cannot burn main veTokenId");
        veToken.merge(_fromId, _toId);
    }

    // extend lock time for veToken to increase voting power
    function increaseUnlockTime(uint256 _lock_duration) external onlyManager {
        veToken.increase_unlock_time(veTokenId, _lock_duration);
        emit IncreaseTime(msg.sender, veTokenId, _lock_duration);
    }

    // transfer an amount of base token to this address and lock into veToken
    function depositBaseToken(uint256 _amount) external {
        baseToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        uint256 baseBal = baseToken.balanceOf(address(this)).sub(storedRewardBalance[address(baseToken)]);
        if (_amount > baseBal) {
            _amount = baseBal;
        }
        veToken.increase_amount(veTokenId, _amount);
        emit IncreaseAmount(msg.sender, veTokenId, _amount);
    }

    // vote for emission weights
    function vote(uint256 _veTokenId, address[] calldata _tokenVote, int256[] calldata _weights)
        external
        onlyManager {
        voter.vote(_veTokenId, _tokenVote, _weights);
    }

    // reset current votes
    function resetVote(uint256 _veTokenId) external onlyManager {
        voter.reset(_veTokenId);
    }

    // whitelist new token
    function whitelist(address _token) external onlyManager {
        voter.whitelist(_token, veTokenId);
    }

    // pause deposits to gauges
    function pause() public onlyManager {
        _pause();
    }

    // unpause deposits to gauges
    function unpause() external onlyManager {
        _unpause();
    }

    // detach veToken from a gauge
    function withdrawVeTokenFromGauge(uint256 _pid, uint256 _veTokenId) external onlyManager {
        withdrawVeTokenFromManyGauges(_pid, _pid, _veTokenId);
    }

    // detach veToken from many gauges
    function withdrawVeTokenFromManyGauges(uint256 _fromId, uint256 _toId, uint256 _veTokenId) public onlyManager {
        require(_fromId <= _toId, "fromId > toId");
        while (_fromId <= _toId) {
            updatePool(_fromId);
            PoolInfo memory pool = poolInfo[_fromId];
            IGauge(pool.gauge).withdrawToken(0, _veTokenId);
            _fromId = _fromId.add(1);
        }
    }

    // transfer veToken to another address, must be detached from all gauges first
    function transferVeToken(address _to, uint256 _veTokenId) external onlyOwner {
        if (veTokenId == _veTokenId) {
            veTokenId = 0;
        }
        veToken.safeTransferFrom(address(this), _to, _veTokenId);
        emit TransferVeToken(msg.sender, _to, _veTokenId);
    }

    // Safe erc20 transfer function, just in case if rounding error causes pool to not have enough reward tokens.
    function safeTransfer(IERC20 token, address _to, uint256 _amount) internal {
        uint256 bal = token.balanceOf(address(this));
        if (_amount > bal) {
            token.safeTransfer(_to, bal);
        } else {
            token.safeTransfer(_to, _amount);
        }
    }

    // confirmation required for receiving veToken to smart contract
    function onERC721Received(
        address operator,
        address from,
        uint tokenId,
        bytes calldata data
    ) external view returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        require(msg.sender == address(veToken), "!veToken");
        return bytes4(keccak256("onERC721Received(address,address,uint,bytes)"));
    }
}