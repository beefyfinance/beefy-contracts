// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "./ICakeBoostStrategy.sol";
import "./ICakeV2Chef.sol";
import "./ICakePool.sol";
import "../Common/DelegateManager.sol";

contract VeCakeStaker is ERC20, ReentrancyGuard, DelegateManager {
    using SafeERC20 for IERC20;

    // Addresses used
    IERC20 public want;
    ICakePool public veCake;
    address public cakeBatch;

    // Duration of lock
    uint256 public constant MAX_DURATION = 365 days;
    uint256 public duration;

    // Our reserve integers 
    uint16 public constant MAX = 10000;
    uint256 public reserveRate;
     
    // beCake fee taken from strats
    uint256 public beTokenShare;

    // Bool switches
    bool public payRewards;
    bool public lock;

    // Strategy mapping 
    mapping(address => mapping (uint256 => address)) public whitelistedStrategy;
    mapping(address => address) public replacementStrategy;

    // Contract Events
    event DepositWant(uint256 tvl);
    event Withdraw(uint256 tvl);
    event RecoverTokens(address token, uint256 amount);
    event UpdatedReserveRate(uint256 newRate);
    event UpdatedDuration(uint256 newDuration);
    event UpdatedLock(bool update);
    event UpdatedPayRewards(bool update);
    event RewardsSkimmed(uint256 rewardAmount);
    event NewBeTokenShare(uint256 oldShare, uint256 newShare);
    event NewCakeBatch(address oldBatch, address newBatch);

    constructor(
        address _veCake,
        uint256 _reserveRate,
        address _cakeBatch,
        uint256 _beTokenShare,
        bytes32 _id,
        address _keeper,
        string memory _name,
        string memory _symbol
    ) DelegateManager(_keeper, _id) ERC20(_name, _symbol) {
        cakeBatch = _cakeBatch;
        veCake = ICakePool(_veCake);
        want = IERC20(veCake.token());
        reserveRate = _reserveRate;

        // Cannot be more than 10%
        require(_beTokenShare <= 1000, "Too Much");
        beTokenShare = _beTokenShare;

        want.safeApprove(address(veCake), type(uint256).max);
    }

    // Checks that caller is the strategy assigned to a specific PoolId in a boosted chef.
    modifier onlyWhitelist(address _cakeChef, uint256 _pid) {
        require(whitelistedStrategy[_cakeChef][_pid] == msg.sender, "!whitelisted");
        _;
    }

    // Helper function for depositing full balance of want
    function depositAll() external {
        _deposit(want.balanceOf(msg.sender));
    }

    // Deposit an amount of want
    function deposit(uint256 _amount) external {
        _deposit(_amount);
    }

    // Deposits Cakes and mint beCake, harvests and checks for veCake deposit opportunities first
    function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
        harvestAndDepositCake();
        uint256 _pool = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfWant();
        _amount = _after - _pool; // Additional check for deflationary tokens

        _mint(msg.sender, _amount);
        emit DepositWant(totalCakes());
    
    }

    // Withdraw capable if we have enough Cakes in the contract
    function withdraw(uint256 _amount) public {
        require(_amount <= withdrawableBalance(), "Not enough Cakes");
        _burn(msg.sender, _amount);
        want.safeTransfer(msg.sender, _amount);
        emit Withdraw(totalCakes());
    }

    function harvestAndDepositCake() public {
        // If we have an oustanding Cake reward we send that amount to the Cake Batch
        if (payRewards) {
            uint256 rewards = outstandingReward();  
            uint256 availableCakes = balanceOfWant();
            if (rewards > 0 && availableCakes > 0) {
                rewards = rewards <= availableCakes ? rewards : availableCakes;
                want.safeTransfer(cakeBatch, rewards);
                emit RewardsSkimmed(rewards);
            }
        }

        // Check for additional lock opportunities
        if (lock) {
            uint256 cakeBalance = balanceOfWant();
            uint256 required = requiredReserve();
            (,,uint256 lockTime) = lockInfo();
            if (cakeBalance > required) {
                // If we have more Cakes then needed in reserve we lock more
                uint256 timelockableCakes = cakeBalance - required;
                veCake.deposit(timelockableCakes, lockTime);
            } 
        }
    }

    // Total Cakes in veCake contract and beCake contract
    function totalCakes() public view returns (uint256) {
        return balanceOfWant() + balanceOfCakeInVe();
    }

    // Calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // Calculate how much 'Cake' is held by the Cake Pool contract
    function balanceOfCakeInVe() public view returns (uint256) {
        (uint256 shares,,uint256 cakesAtLastAction,,,,uint256 boostedShares,,) = veCake.userInfo(address(this));
        uint256 userCakes = (veCake.balanceOf() * shares) / veCake.totalShares() - boostedShares;
        uint256 fee = ((userCakes - cakesAtLastAction) * veCake.performanceFeeContract()) / 10000;
        return userCakes - fee;
    }

     // Withdrawable Balance 
    function withdrawableBalance() public view returns (uint256) {
        uint256 wantBal = balanceOfWant();
        uint256 rewardBal = outstandingReward();
        if (payRewards) {
            return wantBal > rewardBal ? wantBal - rewardBal : 0;
        } else {
            return wantBal;
        }
    }

     // Our reserve Cakes held in the contract to enable withdraw capabilities
    function requiredReserve() public view returns (uint256 withdrawReserve) {
        // We calculate allocation for reserve of the total staked Cakes.
        withdrawReserve = balanceOfCakeInVe() * reserveRate / MAX;
    }

    // Extra Cakes are rewarded back to stakers
    function outstandingReward() public view returns (uint256 rewardReserve) {
        if (totalCakes() <= totalSupply()) {
            rewardReserve = 0;
        } else {
            rewardReserve = totalCakes() - totalSupply();
        }
    }

    // What is our end timestamp and how much time remaining in lock? 
    function lockInfo() public view returns (uint256 endLock, uint256 lockRemaining, uint256 lockExtension) {
        (,,,,,endLock,,,) = veCake.userInfo(address(this));
        lockRemaining = endLock > block.timestamp ? endLock - block.timestamp : 0;
        lockExtension = duration > lockRemaining ? duration - lockRemaining : 0;
    }

    // Prevent any further 'want' deposits and remove approval
    function pause() public onlyManager {
        _pause();
        want.safeApprove(address(veCake), 0);
    }

    // Allow 'want' deposits again and reinstate approval
    function unpause() external onlyManager {
        _unpause();
        want.safeApprove(address(veCake), type(uint256).max);
    }

    // Can only be triggered once the lock is up
    function unlock() external onlyManager {
        (,uint256 remaining,) = lockInfo();
        require (remaining == 0, "!Unlock");
        (,,,,,,,bool locked,) = veCake.userInfo(address(this));

        if (locked) {
            veCake.unlock(address(this));
        }

        veCake.withdrawAll();
    }

    // Pass through a deposit to a boosted chef
    function deposit(address _cakeChef, uint256 _pid, uint256 _amount) external onlyWhitelist(_cakeChef, _pid) {
        // Grab needed pool info
        address _underlying = ICakeV2Chef(_cakeChef).lpToken(_pid);

        // Take before balances snapshot and transfer want from strat
        uint256 cakeBefore = balanceOfWant(); // How many Cake's the strategy holds
        IERC20(_underlying).safeTransferFrom(msg.sender, address(this), _amount);

        ICakeV2Chef(_cakeChef).deposit(_pid, _amount);
        uint256 cakeDiff = balanceOfWant() - cakeBefore; // Amount of Cakes the Chef sent us
        
        // Send beCake Batch their Cakes
        if (cakeDiff > 0) {
            uint256 batchCakes = cakeDiff * beTokenShare / MAX;
            want.safeTransfer(cakeBatch, batchCakes);

            uint256 remaining = cakeDiff - batchCakes;
            want.safeTransfer(msg.sender, remaining);
        }
    }

    // Pass through a withdrawal from boosted chef
    function withdraw(address _cakeChef, uint256 _pid, uint256 _amount) external onlyWhitelist(_cakeChef, _pid) {
        // Grab needed pool info
        address _underlying = ICakeV2Chef(_cakeChef).lpToken(_pid);

        uint256 cakeBefore = balanceOfWant(); // How many Cake's strategy the holds
        
        ICakeV2Chef(_cakeChef).withdraw(_pid, _amount);
        uint256 cakeDiff = balanceOfWant() - cakeBefore; // Amount of Cakes the Chef sent us
        IERC20(_underlying).safeTransfer(msg.sender, _amount);

        if (cakeDiff > 0) {
            // Send beCake Batch their Cakes
            uint256 batchCakes = cakeDiff * beTokenShare / MAX;
            want.safeTransfer(cakeBatch, batchCakes);

            uint256 remaining = cakeDiff - batchCakes;
            want.safeTransfer(msg.sender, remaining);
        }
    }

    // Emergency withdraw losing all Cake rewards from boosted chef
    function emergencyWithdraw(address _cakeChef, uint256 _pid) external onlyWhitelist(_cakeChef, _pid) {
        address _underlying = ICakeV2Chef(_cakeChef).lpToken(_pid);
        uint256 _before = IERC20(_underlying).balanceOf(address(this));
        ICakeV2Chef(_cakeChef).emergencyWithdraw(_pid);
        uint256 _balance = IERC20(_underlying).balanceOf(address(this)) - _before;
        IERC20(_underlying).safeTransfer(msg.sender, _balance);
    }


    /**
     * @dev Updates address of the Cake Batch.
     * @param _cakeBatch new cakeBatch address.
     */
    function setCakeBatch(address _cakeBatch) external onlyOwner {
        emit NewCakeBatch(cakeBatch, _cakeBatch);
        cakeBatch = _cakeBatch;
    }

    /**
     * @dev Updates share for the Batch.
     * @param _newBeTokenShare new share.
     */
    function setBeTokenShare(uint256 _newBeTokenShare) external onlyManager {
        require(_newBeTokenShare <= 1000, "too much");
        emit NewBeTokenShare(beTokenShare, _newBeTokenShare);
        beTokenShare = _newBeTokenShare;
    }

    // Set Lock Duration
    function setDuration(uint256 _days) external onlyOwner {
        require(_days * 1 days <= MAX_DURATION, "Higher than max");
        require(_days * 1 days >= 1 weeks || _days == 0, "Week min");
        duration = _days * 1 days;
        emit UpdatedDuration(duration);
    }

    // Set Lock 
    function setLock(bool _lock) external onlyOwner {
        lock = _lock;
        emit UpdatedLock(lock);
    }

    // Set reward bool
    function setPayRewards(bool _payRewards) external onlyOwner {
        payRewards = _payRewards;
        emit UpdatedPayRewards(payRewards);
    }

    // Adjust reserve rate 
    function adjustReserve(uint256 _rate) external onlyOwner {
        require(_rate <= MAX, "Higher than max");
        reserveRate = _rate;
        emit UpdatedReserveRate(_rate);
    }

    /**
     * @dev Whitelists a strategy address to interact with the Boosted Chef and gives approvals.
     * @param _strategy new strategy address.
     */
    function whitelistStrategy(address _strategy) external onlyManager {
        IERC20 _want = ICakeBoostStrategy(_strategy).want();
        uint256 _pid = ICakeBoostStrategy(_strategy).poolId();
        address _cakeChef = ICakeBoostStrategy(_strategy).chef();
        (uint256 stratBal,,) = ICakeV2Chef(_cakeChef).userInfo(_pid, address(this));
        require(stratBal == 0, "!inactive");

        _want.safeApprove(_cakeChef, 0);
        _want.safeApprove(_cakeChef, type(uint256).max);
        whitelistedStrategy[_cakeChef][_pid] = _strategy;
    }

    /**
     * @dev Removes a strategy address from the whitelist and remove approvals.
     * @param _strategy remove strategy address from whitelist.
     */
    function blacklistStrategy(address _strategy) external onlyManager {
        IERC20 _want = ICakeBoostStrategy(_strategy).want();
        uint256 _pid = ICakeBoostStrategy(_strategy).poolId();
        address _cakeChef = ICakeBoostStrategy(_strategy).chef();
        _want.safeApprove(_cakeChef, 0);
        whitelistedStrategy[_cakeChef][_pid] = address(0);
    }

    /**
     * @dev Prepare a strategy to be retired and replaced with another.
     * @param _oldStrategy strategy to be replaced.
     * @param _newStrategy strategy to be implemented.
     */
    function proposeStrategy(address _oldStrategy, address _newStrategy) external onlyManager {
        require(ICakeBoostStrategy(_oldStrategy).poolId() == ICakeBoostStrategy(_newStrategy).poolId(), "!pid");
        replacementStrategy[_oldStrategy] = _newStrategy;
    }

    /**
     * @dev Switch over whitelist from one strategy to another for a gauge.
     * @param _pid pid for which the new strategy will be whitelisted.
     */
    function upgradeStrategy(address _cakeChef, uint256 _pid) external onlyWhitelist(_cakeChef, _pid) {
        whitelistedStrategy[_cakeChef][_pid] = replacementStrategy[msg.sender];
    }

    // Recover any tokens sent on error
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!token");

        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit RecoverTokens(_token, _amount);

    }
}
