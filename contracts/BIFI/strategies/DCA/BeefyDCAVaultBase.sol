// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin-4/contracts/utils/math/Math.sol";
import "./IMooVault.sol";
import "./IDCAStrategy.sol";
import "./BeefyERC721Enumerable.sol";

pragma solidity ^0.8.0;
contract BeefyDCAVaultBase is BeefyERC721Enumerable, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Upgrade struct in case we need to upgrade the underlying strategy
    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }
    StratCandidate public stratCandidate;

    // Addresses needed 
    IERC20 public immutable want; 
    IERC20 public immutable reward;
    IDCAStrategy public strategy;

    // Reward distribution variables
    uint256 public constant DURATION = 1 days;
    uint256 private constant ONE = 1e18;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    // NFT variables
    uint256 public vaultCount;
    uint256 private _underlyingBalanceTotal;
    uint256 public approvalDelay;

    // balance mappings
    mapping(uint256 => uint256) public userRewardPerTokenPaid;
    mapping(uint256 => uint256) public rewards;
    mapping(uint256 => uint256) public underlyingBalance;

    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    event RewardAdded(uint256 reward);
    event Deposit(address indexed user, uint256 id, uint256 amount);
    event Withdraw(address indexed user, uint256 id,  uint256 amount);
    event RewardPaid(address indexed user, uint256 id,  uint256 reward);
    event CreateVault(address indexed user, uint256 id);
    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);

    constructor(
        string memory _name,
        string memory _symbol,
        address _want,
        address _strategy,
        address _reward, 
        uint256 _approvalDelay
    ) ERC721(_name, _symbol) {
        strategy = IDCAStrategy(_strategy);
        want = IERC20(_want);
        reward = IERC20(_reward);
        approvalDelay = _approvalDelay;
    }

    // We update the accumulated reward for each NFT id with this modifier
    modifier updateReward(uint256 account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != 0) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    // The available want we can send to earn in the strategy
    function available() public view returns (uint256) {
        return want.balanceOf(address(this));
    }
    
    function underlyingBalanceTotal() public view returns (uint256) {
        return _underlyingBalanceTotal;
    }

    // Vault deploys funds to the underlying strategy
    function earn() public {
        uint _bal = available();
        want.safeTransfer(address(strategy), _bal);
        strategy.deposit();
    }

    // Helper function to deposit all 
    function depositAll(uint256 _id) external {
        uint256 amount = want.balanceOf(msg.sender);
        deposit(_id, amount);
    }

    // Deposit: Will Deposit into beefy vault and account for underlying deposited. It will mint a vault if you dont own one by passing through 0 as _id. 
    // Anyone can deposit on behalf an id but only those who own the id can withdraw.
    function deposit(uint256 _id, uint256 _amount) public nonReentrant updateReward(_id) returns (uint256) {
        require(_amount > 0, "Cannot stake 0");
        strategy.beforeDeposit();
        if (_id == 0) {
            _id = vaultCount + 1;
            vaultCount = vaultCount + 1;
            _mint(msg.sender, _id);
            emit CreateVault(msg.sender, _id);
        }

        _requireMinted(_id);
        want.safeTransferFrom(msg.sender, address(this), _amount);
        underlyingBalance[_id] = underlyingBalance[_id] + _amount;
        _underlyingBalanceTotal = _underlyingBalanceTotal + _amount;
        earn();

        emit Deposit(msg.sender, _id, _amount);

        return _id;
    }

    // Withdraw: Withdraws amount from strategy and send to owner of the NFT. Only NFT owner can withdraw.
    function withdraw(uint256 _id, uint256 _amount) public nonReentrant updateReward(_id) {
        require(ownerOf(_id) == msg.sender, "!owner");
        require(underlyingBalance[_id] >= _amount, "balance is less than requested");
        require(_amount > 0, "Cannot withdraw 0");

        underlyingBalance[_id] = underlyingBalance[_id] - _amount;
        _underlyingBalanceTotal = _underlyingBalanceTotal - _amount;

        uint256 wantBal = want.balanceOf(address(this));

        strategy.withdraw(_amount);
        uint _after = want.balanceOf(address(this));
        uint _diff = _after - wantBal;

        want.safeTransfer(msg.sender, _diff);
        emit Withdraw(msg.sender, _id, wantBal);

    }
    
    // Exit entirely from vault and claim all exisiting rewards. 
    function exit(uint256 _id) external {
        getReward(_id);
        withdraw(_id, underlyingBalance[_id]);
    }
    

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (underlyingBalanceTotal() == 0) {
            return rewardPerTokenStored;
        }

        uint256 time = lastTimeRewardApplicable() - lastUpdateTime;
        uint256 rewardRateTimesOne = rewardRate * ONE;
        
        uint256 equation = time * rewardRateTimesOne / underlyingBalanceTotal();
        return rewardPerTokenStored + equation;
    }

    function earned(uint256 account) public view returns (uint256) {
        return underlyingBalance[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / ONE + rewards[account];
    }

    function getReward(uint256 _id) public updateReward(_id) {
        require (ownerOf(_id) == msg.sender, "!id owner");
        uint256 _reward = earned(_id);
        if (_reward > 0) {
            rewards[_id] = 0;
            reward.safeTransfer(msg.sender, _reward);
            emit RewardPaid(msg.sender, _id, _reward);
        }
    }

    // Merge two NFTs together since a user address can only own one, claims owed rewards for to user first. 
    function merge(address to) external {
        uint256 toId = tokenOfOwnerByIndex(to, 0);
        uint256 fromId = tokenOfOwnerByIndex(msg.sender, 0);
        uint256 fromBal = underlyingBalance[fromId];

        getReward(fromId);
        underlyingBalance[fromId] = 0;
        _burn(fromId);
        underlyingBalance[toId] += fromBal;
    }


    // Only strategy can notify. 
    function notifyRewardAmount(uint256 _reward)
        external
        updateReward(0)
    {
        require(msg.sender == address(strategy), "!strategy");
        if (block.timestamp >= periodFinish) {
            rewardRate = _reward / DURATION;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = _reward + leftover / DURATION;
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + DURATION;
        emit RewardAdded(_reward);
    }

    // Sets the new strat candidate for the upgrade. Checks to make sure want and reward match the proposed strategy.
    function proposeStrat(address _implementation) public onlyOwner {
        require(address(this) == IDCAStrategy(_implementation).vault(), "Proposal not valid for this Vault");
        require(address(want) == IDCAStrategy(_implementation).want(), "Different want");
        require(address(reward) == IDCAStrategy(_implementation).reward(), "Different reward");
        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });

        emit NewStratCandidate(_implementation);
    }

    /** 
     * @dev It switches the active strat for the strat candidate. After upgrading, the 
     * candidate implementation is set to the 0x00 address, and proposedTime to a time 
     * happening in +100 years for safety. 
     */

    function upgradeStrat() public onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime + approvalDelay < block.timestamp, "Delay has not passed");

        emit UpgradeStrat(stratCandidate.implementation);

        strategy.retireStrat();
        strategy = IDCAStrategy(stratCandidate.implementation);
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;

        earn();
    }

    // View function for UI
    function userInfo(address _user) external view returns (uint256 id, uint256 principal, uint256 interest) {
        id = tokenOfOwnerByIndex(_user, 0);
        principal = underlyingBalance[id];
        interest = earned(id);
    }

    // In case someone sends tokens to the contract by mistake, we can recover. Cannot recover want or reward. 
     function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!staked");
        require(_token != address(reward), "!reward");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

}