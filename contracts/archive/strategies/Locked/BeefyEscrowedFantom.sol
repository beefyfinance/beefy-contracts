// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/utils/math/SafeMath.sol";
import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/security/ReentrancyGuard.sol";

import "./ISFC.sol";
import "./LockedAssetManager.sol";

interface IWrappedNative is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

contract BeefyEscrowedFantom is ERC20, ReentrancyGuard, LockedAssetManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Important Variables
    IERC20 public want;
    ISFC public stakingContract;
    uint256 public validatorID;
    address public validator;
    uint256 public oneWeek = 1 weeks;

    // Withdraw Variables
    uint256 public wrID;
    uint256 public withdrawalTime;
    uint256 public withdrawalPeriodTime = 60 * 60 * 24 * 7;
    bool public withdrawEnabled = false;

    // Validator share so that limit is never hit
    uint256 public validatorShare = 1000;
    uint256 public validatorMax = 15000;

    event DepositWant(uint256 tvl);
    event ClaimRewards(uint256 rewardsClaimed);
    event RecoverTokens(address token, uint256 amount);

    constructor(
        address _want,
        address _stakingContract,
        uint256 _validatorID,
        address _validator,
        address _keeper,
        address _rewardPool,
        string memory _name,
        string memory _symbol
    ) LockedAssetManager(_keeper, _rewardPool) ERC20( _name, _symbol) {
        validatorID = _validatorID;
        validator = _validator;
        want = IERC20(_want);
        stakingContract = ISFC(_stakingContract);
    }

    // helper function for depositing full balance of want
    function depositAll() external {
        uint256 _amount = want.balanceOf(msg.sender);
        want.safeTransferFrom(msg.sender, address(this), _amount);
        IWrappedNative(address(want)).withdraw(_amount);
        _deposit(msg.sender, _amount);
    }

    // deposit an amount of want
    function deposit(uint256 _amount) external {
        want.safeTransferFrom(msg.sender, address(this), _amount);
        IWrappedNative(address(want)).withdraw(_amount);
        _deposit(msg.sender, _amount);
    }

    // deposit unwrapped 
    function depositNative() external payable { 
        _deposit(msg.sender, msg.value);
    }

    // deposit 'want' and lock
    function _deposit(address _user, uint256 _amount) internal nonReentrant whenNotPaused {
        if (_amount > 0) {
            uint256 valAmt = _amount.mul(validatorShare).div(validatorMax);
            (bool sent,) = validator.call{value: valAmt}("");
            require(sent, "Failed to send Ether");

            uint256 remaining = _amount.sub(valAmt);
            stakingContract.delegate{value: remaining}(validatorID);

            if (validatorLockDuration() > currentLockDuration()){
                if (balanceOfLocked() > 0) {
                    stakingContract.relockStake(validatorID, lockTime(), balanceOfUnlocked());
                } else {
                    stakingContract.lockStake(validatorID, lockTime(), balanceOfUnlocked());
                }
            }

            _mint(_user, _amount);
            emit DepositWant(balanceOfLocked());
        }
    }

    // Withdraw funds, only can happen if we undelegate with penalty and after 7 day waiting period
    function withdraw(uint256 _shares) external {
        require (withdrawEnabled, "Withdraw is not enabled");
        uint256 r = (balanceOfWant().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        (bool sent,) = msg.sender.call{value: r}("");
        require(sent, "Failed to send Ether");
    }

    // timestamp at which 'want' is unlocked
    function currentUnlockTime() external view returns (uint256 time) {
        (,,time,) = stakingContract.getLockupInfo(address(this), validatorID);
    }

    // duration at which 'want' is unlocked
    function currentLockDuration() public view returns (uint256 time) {
        (,,,time) = stakingContract.getLockupInfo(address(this), validatorID);
    }

    // validators end lock time 
    function validatorUnlockTime() public view returns (uint256 time) {
        (,,time,) = stakingContract.getLockupInfo(validator, validatorID);
    }

     //  duration at which 'want' is unlocked
    function validatorLockDuration() public view returns (uint256 time) {
        (,,,time) = stakingContract.getLockupInfo(validator, validatorID);
    }

    // calculate how much duration we should lock 
    function lockTime() internal view returns (uint256 time) {
        uint256 suggestedLockUp = validatorUnlockTime().sub(block.timestamp).sub(oneWeek);
        if (currentLockDuration() >= suggestedLockUp) {
            time = currentLockDuration();
        } else {
            time = suggestedLockUp;
        }
    }

    // calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return address(this).balance;
    }

    // The amount of locked want in the staking contract
    function balanceOfLocked() public view returns (uint256) {
        return stakingContract.getLockedStake(address(this), validatorID);
    }

    // Balance of unlocked want in the staking contract 
    function balanceOfUnlocked() public view returns (uint256) {
        return stakingContract.getUnlockedStake(address(this), validatorID);
    }

    // pending witdrawal request information 
    function pendingWithdrawalRequest() public view returns (uint256 time, uint256 amount) {
        (,time, amount) = stakingContract.getWithdrawalRequest(address(this), validatorID, wrID);
    }

    // pending reward balance 
    function pendingStakingRewards() external view returns (uint256) {
        return stakingContract.pendingRewards(address(this), validatorID);
    }

    // enable withdraw of funds 
    function enableWithdraw() external onlyOwner {
        _pause();
        stakingContract.unlockStake(validatorID, balanceOfLocked());
        stakingContract.undelegate(validatorID, wrID, balanceOfUnlocked());
        withdrawalTime = withdrawalPeriodTime.add(block.timestamp);
    }

    // withdraw all want from staking contract 
    function withdrawFromStaking() external onlyOwner {
        require(block.timestamp >= withdrawalTime, "It takes 7 Days to withdraw");
        stakingContract.withdraw(validatorID, wrID);
        wrID = wrID.add(1);
        withdrawEnabled = true;
    }

    // lock if we can lock and if there is a balanceOfUnlocked
    function lockFunds() external {
        require(validatorLockDuration() > currentLockDuration(), "Validator needs more lock time");
        stakingContract.relockStake(validatorID, lockTime(), balanceOfUnlocked());
    }

    // Relock stake 
    function relockFunds() external onlyOwner {
        _unpause();
        uint256 relockAmount = balanceOfWant();
        stakingContract.delegate{value: relockAmount}(validatorID);
        stakingContract.relockStake(validatorID, lockTime(), balanceOfUnlocked());
        withdrawEnabled = false;
    }

    // prevent any further 'want' deposits and remove approval
    function pause() public onlyManager {
        _pause();
    }

    // allow 'want' deposits again and reinstate approval
    function unpause() external onlyManager {
        _unpause();
    }

    // pass through rewards from the fee distributor
    function claimStakingReward() external onlyRewardPool {
        uint256 _before = balanceOfWant();
        stakingContract.claimRewards(validatorID);
        uint256 _balance = balanceOfWant().sub(_before);
        IWrappedNative(address(want)).deposit{value: _balance}();
        want.safeTransfer(rewardPool, _balance);
        emit ClaimRewards(_balance);
    }

    // recover any unknown tokens
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!token");

        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit RecoverTokens(_token, _amount);
    }

    receive () external payable {}
}
