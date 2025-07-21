// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/security/ReentrancyGuard.sol";

import "./IeQI.sol";
import "./QiManager.sol";


contract BeefyQI is ERC20, ReentrancyGuard, QiManager {
    using SafeERC20 for IERC20;

    // Addresses used
    IERC20 public want;
    IeQI public eQI;

    // Our reserve integers 
    uint16 public constant MAX = 10000;
    uint32 public constant MAX_LOCK = 60108430;

    uint256 public reserveRate; 

    event DepositWant(uint256 tvl);
    event Withdraw(uint256 tvl);
    event RecoverTokens(address token, uint256 amount);
    event UpdatedReserveRate(uint256 newRate);

    constructor( 
        address _eQI,
        address _keeper,
        uint256 _reserveRate,
        address _rewardPool, 
        string memory _name,
        string memory _symbol
    ) QiManager(_keeper, _rewardPool) ERC20(_name, _symbol) {
        eQI = IeQI(_eQI);
        want = IERC20(eQI.Qi());
        reserveRate = _reserveRate;

        want.safeApprove(address(eQI), type(uint256).max);
    }

    // helper function for depositing full balance of want
    function depositAll() external {
        _deposit(want.balanceOf(msg.sender));
    }

    // deposit an amount of want
    function deposit(uint256 _amount) external {
        _deposit(_amount);
    }

    // Deposits QI and mint beQI, harvests and checks for eQI deposit opportunities first. 
    function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
        harvestAndDepositQI();
        uint256 _pool = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfWant();
        _amount = _after - _pool; // Additional check for deflationary tokens

        if (_amount > 0) {
            _mint(msg.sender, _amount);
            emit DepositWant(totalQI());
        }
    }

    // Withdraw capable if we have enough QI in the contract. 
    function withdraw(uint256 _amount) external {
        require(_amount <= withdrawableBalance(), "Not enough QI");
            _burn(msg.sender, _amount);
            want.safeTransfer(msg.sender, _amount);
            emit Withdraw(totalQI());
    }

    // We harvest QI on every deposit, if we can deposit to earn more eQI we deposit based on required reserve
    function harvestAndDepositQI() public { 
        if (totalQI() > 0) {
            // How many blocks are we going to lock for? 
            (,, uint256 lockExtension) = lockInfo();
            if (balanceOfWant() - outstandingReward() > requiredReserve()) {
                uint256 availableBalance = balanceOfWant() - outstandingReward() - requiredReserve();
                eQI.enter(availableBalance, lockExtension);
            } else {
                // Extend max lock
                eQI.enter(0, lockExtension);
            }
        }
           
        harvest();
    }

    // claim the QI
    function harvest() public {
        uint256 _amount = outstandingReward();
        if (_amount > 0) {
            want.safeTransfer(address(rewardPool), _amount);
            rewardPool.notifyRewardAmount(_amount);
        }
    }

    // Our required QI held in the contract to enable withdraw capabilities
    function requiredReserve() public view returns (uint256 reqReserve) {
        // We calculate allocation for reserve of the total staked QI.
        reqReserve = balanceOfQiInVe() * reserveRate / MAX;
    }

    // How much reward is available? We subtract total QIs from the total supply of beQI.  
    function outstandingReward() public view returns (uint256) {
        return totalQI() - totalSupply();
    }

    // Total QI in eQI contract and beQI contract. 
    function totalQI() public view returns (uint256) {
        return balanceOfWant() + balanceOfQiInVe();
    }

    // Calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // Withdrawable Balance 
    function withdrawableBalance() public view returns (uint256) {
        return balanceOfWant() - outstandingReward();
    }

    // Calculate how much QI Power we have
    function qiPower() external view returns (uint256) {
        return eQI.balanceOf(address(this));
    }

    // How many QI we got earning? 
    function balanceOfQiInVe() public view returns (uint256 qis) {
        (qis,) = eQI.userInfo(address(this));
    }

    // What is our end block and blocks remaining in lock? 
    function lockInfo() public view returns (uint256 endBlock, uint256 blocksRemaining, uint256 lockExtension) {
        (, endBlock) = eQI.userInfo(address(this));
        blocksRemaining = endBlock > block.number ? endBlock - block.number : 0;
        lockExtension = MAX_LOCK - blocksRemaining;
    }

    // Prevent any further 'want' deposits and remove approval
    function pause() public onlyManager {
        _pause();
        want.safeApprove(address(eQI), 0);
    }

    // allow 'want' deposits again and reinstate approval
    function unpause() external onlyManager {
        _unpause();
        want.safeApprove(address(eQI), type(uint256).max);
    }

    // panic the vault if emergency is enabled by QI
    function panic() external onlyManager { 
        pause();
        eQI.emergencyExit();
    }

    // Adjust reserve rate 
    function adjustReserve(uint256 _rate) external onlyOwner { 
        require(_rate <= MAX, "Higher than max");
        reserveRate = _rate;
        emit UpdatedReserveRate(_rate);
    }

    // recover any tokens sent on error
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!token");
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit RecoverTokens(_token, _amount);
    }
}
