// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/security/ReentrancyGuard.sol";

import "./ICakeV2Chef.sol";
import "./ICakePool.sol";
import "./CakeChefManager.sol";

contract VeCakeStaker is ERC20, ReentrancyGuard, CakeChefManager {
    using SafeERC20 for IERC20;

    // Addresses used
    IERC20 public want;
    ICakePool public veCake;

    // Duration of lock
    uint256 public constant DURATION = 31536000;

    // Our reserve integers 
    uint16 public constant MAX = 10000;
    uint256 public reserveRate;


    // Contract Events
    event DepositWant(uint256 tvl);
    event Withdraw(uint256 tvl);
    event RecoverTokens(address token, uint256 amount);
    event UpdatedReserveRate(uint256 newRate);
    event RewardsSkimmed(uint256 rewardAmount);

    constructor(
        address _veCake,
        uint256 _reserveRate,
        address _cakeBatch,
        uint256 _beCakeShare,
        address _keeper,
        string memory _name,
        string memory _symbol
    ) CakeChefManager(_keeper, _cakeBatch, _beCakeShare) ERC20(_name, _symbol) {
        veCake = ICakePool(_veCake);
        want = IERC20(veCake.token());
        reserveRate = _reserveRate;

        want.safeApprove(address(veCake), type(uint256).max);
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
        uint256 rewards = outstandingReward();  
        if (rewards > 0) {
            want.safeTransfer(cakeBatch, rewards);
            emit RewardsSkimmed(rewards);
        }


        // Check for additional lock opportunities
        if (totalCakes() > 0) {
            uint256 cakeBalance = balanceOfWant();
            uint256 required = requiredReserve();
            (,,uint256 lockTime) = lockInfo();
            if (cakeBalance > required) {
                // If we have more Cakes then needed in reserve we lock more
                uint256 timelockableCakes = cakeBalance - required;
                veCake.deposit(timelockableCakes, lockTime);
            } else {
                // We have to deposit the min to extend lock
                uint256 minDeposit = veCake.MIN_DEPOSIT_AMOUNT();
                if (cakeBalance > minDeposit) {
                    veCake.deposit(minDeposit, lockTime);
                }
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
    function balanceOfCakeInVe() public view returns (uint256 locked) {
        (,,,,,,,,locked) = veCake.userInfo(address(this));
     }

     // Withdrawable Balance 
    function withdrawableBalance() public view returns (uint256) {
        return balanceOfWant() - outstandingReward();
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
        lockExtension = DURATION - lockRemaining;
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

        uint256 cakeLocked = balanceOfCakeInVe();
        veCake.unlock(address(this));
        veCake.withdrawByAmount(cakeLocked);
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
            uint256 batchCakes = cakeDiff * beCakeShare / MAX;
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
            uint256 batchCakes = cakeDiff * beCakeShare / MAX;
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

    // Adjust reserve rate 
    function adjustReserve(uint256 _rate) external onlyOwner {
        require(_rate <= MAX, "Higher than max");
        reserveRate = _rate;
        emit UpdatedReserveRate(_rate);
    }

    // Recover any tokens sent on error
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!token");

        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit RecoverTokens(_token, _amount);

    }
}
