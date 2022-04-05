// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./IJoeChef.sol";
import "./IVeJoe.sol";
import "./ChefManager.sol";

interface IRewarder {
    function rewardToken() external view returns (address);
}

contract VeJoeStaker is ERC20Upgradeable, ReentrancyGuardUpgradeable, ChefManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    // Addresses used
    IERC20Upgradeable public want;
    IVeJoe public veJoe;
    address public immutable native = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    // Our reserve integers 
    uint16 public constant MAX = 10000;
    uint256 public reserveRate; 

    event DepositWant(uint256 tvl);
    event Withdraw(uint256 tvl);
    event RecoverTokens(address token, uint256 amount);
    event UpdatedReserveRate(uint256 newRate);

    function initialize(
        address _veJoe,
        address _keeper,
        address _joeChef,
        uint256 _reserveRate,
        address _joeBatch, 
        uint256 _beJoeShare,
        string memory _name,
        string memory _symbol
    ) public initializer {
        managerInitialize(_joeChef, _keeper, _joeBatch, _beJoeShare);
        veJoe = IVeJoe(_veJoe);
        want = IERC20Upgradeable(veJoe.joe());
        reserveRate = _reserveRate;

        __ERC20_init(_name, _symbol);

        want.safeApprove(address(veJoe), type(uint256).max);
    }

    // helper function for depositing full balance of want
    function depositAll() external {
        _deposit(msg.sender, want.balanceOf(msg.sender));
    }

    // deposit an amount of want
    function deposit(uint256 _amount) external {
        _deposit(msg.sender, _amount);
    }

    // deposit an amount of want on behalf of an address
    function depositFor(address _user, uint256 _amount) external {
        _deposit(_user, _amount);
    }

    // Deposits Joes and mint beJOE, harvests and checks for veJOE deposit opportunities first. 
    function _deposit(address _user, uint256 _amount) internal nonReentrant whenNotPaused {
        harvestAndDepositJoe();
        uint256 _pool = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfWant();
        _amount = _after.sub(_pool); // Additional check for deflationary tokens

        if (_amount > 0) {
            _mint(_user, _amount);
            emit DepositWant(totalJoes());
        }
    }

    // Withdraw capable if we have enough JOEs in the contract. 
    function withdraw(uint256 _amount) public {
        require(_amount < balanceOfWant(), "Not enough JOEs to withdraw");
        _burn(msg.sender, _amount);
        want.safeTransfer(msg.sender, _amount);
        emit Withdraw(totalJoes());
    }

    // We harvest veJOE on every deposit, if we can deposit to earn more veJOE we deposit based on required reserve and bonus
    function harvestAndDepositJoe() public { 
        if (totalJoes() > 0) {
            if (balanceOfWant() > requiredReserve()) {
                uint256 avaialableBalance = balanceOfWant().sub(requiredReserve());
                // we want the bonus for depositing more than 5% of our already deposited joes
                uint256 joesNeededForBonus = balanceOfJoeInVe().mul(veJoe.speedUpThreshold()).div(100);
                if (avaialableBalance > joesNeededForBonus) {
                    veJoe.deposit(avaialableBalance);
                } 
            }
            _harvestVeJoe();
        }
    }

    // claim the veJoes
    function _harvestVeJoe() internal {
        veJoe.claim();
    }

    // Our required JOEs held in the contract to enable withdraw capabilities
    function requiredReserve() public view returns (uint256 reqReserve) {
        // We calculate allocation for 20% or the total supply of contract to the reserve.
        reqReserve = totalJoes().mul(reserveRate).div(MAX);
    }

    // Total Joes in veJOE contract and beJOE contract. 
    function totalJoes() public view returns (uint256) {
        return balanceOfWant().add(balanceOfJoeInVe());
    }

    // calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // calculate how much 'veWant' is held by this contract
    function balanceOfVe() public view returns (uint256) {
        return IERC20Upgradeable(veJoe.veJoe()).balanceOf(address(this));
    }

    // how many joes we got earning ve? 
    function balanceOfJoeInVe() public view returns (uint256 joes) {
        (joes,,,) = veJoe.userInfos(address(this));
    }

     // how many joes we got earning ve? 
    function speedUpTimestamp() public view returns (uint256 time) {
        (,,,time) = veJoe.userInfos(address(this));
    }

    // prevent any further 'want' deposits and remove approval
    function pause() public onlyManager {
        _pause();
        want.safeApprove(address(veJoe), 0);
    }

    // allow 'want' deposits again and reinstate approval
    function unpause() external onlyManager {
        _unpause();
        want.safeApprove(address(veJoe), type(uint256).max);
        uint256 reserveAmt = balanceOfWant().mul(reserveRate).div(MAX);
        veJoe.deposit(balanceOfWant().sub(reserveAmt));
    }

    // panic beJOE, pause deposits and withdraw JOEs from veJoe, we lose all accrued veJOE 
    function panic() external onlyManager {
        pause();
        veJoe.withdraw(balanceOfJoeInVe());
    }

    // pass through a deposit to a boosted chef 
    function deposit(uint256 _pid, uint256 _amount) external onlyWhitelist(_pid) {
        // Grab needed pool info
        (address _underlying,,,,, address _rewarder,,,) = joeChef.poolInfo(_pid);

        // Take before balances snapshot and transfer want from strat
        uint256 joeBefore = balanceOfWant(); // How many Joe's strategy hold    
        IERC20Upgradeable(_underlying).safeTransferFrom(msg.sender, address(this), _amount);

        // Handle a second reward via a rewarder
        address rewardToken;
        uint256 rewardBefore; 
        uint256 nativeBefore;
        if (_rewarder != address(0)) {
            rewardToken = IRewarder(_rewarder).rewardToken();
            rewardBefore = IERC20Upgradeable(rewardToken).balanceOf(address(this));
            if (rewardToken == native) {
                nativeBefore = address(this).balance;
            } 
        }

        joeChef.deposit(_pid, _amount);
        uint256 joeDiff = balanceOfWant().sub(joeBefore); // Amount of Joes the Chef sent us
        
        // Send beJoe Batch their JOEs
        uint256 batchJoes = joeDiff.mul(beJoeShare).div(MAX);
        want.safeTransfer(joeBatch, batchJoes);

        uint256 remaining = joeDiff.sub(batchJoes);
        want.safeTransfer(msg.sender, remaining);

        // Transfer the second reward
        if (_rewarder != address(0)) {
            if (rewardToken == native) {
                uint256 nativeDiff = address(this).balance.sub(nativeBefore);
                (bool sent,) = msg.sender.call{value: nativeDiff}("");
                require(sent, "Failed to send Ether");
            } else {
                uint256 rewardDiff = IERC20Upgradeable(rewardToken).balanceOf(address(this)).sub(rewardBefore);
                IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, rewardDiff);
            }
        }
    }

    // pass through a withdrawal from boosted chef
    function withdraw(uint256 _pid, uint256 _amount) external onlyWhitelist(_pid) {
        // Grab needed pool info
        (address _underlying,,,,, address _rewarder,,,) = joeChef.poolInfo(_pid);

        uint256 joeBefore = balanceOfWant(); // How many Joe's strategy hold  

        // Handle a second reward via a rewarder
        address rewardToken;
        uint256 rewardBefore; 
        uint256 nativeBefore;
        if (_rewarder != address(0)) {
            rewardToken = IRewarder(_rewarder).rewardToken();
            rewardBefore = IERC20Upgradeable(rewardToken).balanceOf(address(this));
            if (rewardToken == native) {
                nativeBefore = address(this).balance;
            } 
        }
        
        joeChef.withdraw(_pid, _amount);
        uint256 joeDiff = balanceOfWant().sub(joeBefore); // Amount of Joes the Chef sent us
        IERC20Upgradeable(_underlying).safeTransfer(msg.sender, _amount);

        // Transfer the second reward
        if (_rewarder != address(0)) {
            if (rewardToken == native) {
                uint256 nativeDiff = address(this).balance.sub(nativeBefore);
                (bool sent,) = msg.sender.call{value: nativeDiff}("");
                require(sent, "Failed to send Ether");
            } else {
                uint256 rewardDiff = IERC20Upgradeable(rewardToken).balanceOf(address(this)).sub(rewardBefore);
                IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, rewardDiff);
            }
        }

          // Send beJoe Batch their JOEs
        uint256 batchJoes = joeDiff.mul(beJoeShare).div(MAX);
        want.safeTransfer(joeBatch, batchJoes);

        uint256 remaining = joeDiff.sub(batchJoes);
        want.safeTransfer(msg.sender, remaining); 
    }

    // emergency withdraw losing all JOE rewards from boosted chef
    function emergencyWithdraw(uint256 _pid) external onlyWhitelist(_pid) {
        (address _underlying,,,,,,,,) = joeChef.poolInfo(_pid);
        uint256 _before = IERC20Upgradeable(_underlying).balanceOf(address(this));
        joeChef.emergencyWithdraw(_pid);
        uint256 _balance = IERC20Upgradeable(_underlying).balanceOf(address(this)).sub(_before);
        IERC20Upgradeable(_underlying).safeTransfer(msg.sender, _balance);
    }

    // Adjust reserve rate 
    function adjustReserve(uint256 _rate) external onlyOwner { 
        require(_rate <= MAX, "Higher than max");
        reserveRate = _rate;
        emit UpdatedReserveRate(_rate);
    }

    // recover any tokens sent on error
    function inCaseTokensGetStuck(address _token, bool _native) external onlyOwner {
         require(_token != address(want), "!token");

        if (_native) {
            uint256 _nativeAmount = address(this).balance;
            (bool sent,) = msg.sender.call{value: _nativeAmount}("");
            require(sent, "Failed to send Ether");
            emit RecoverTokens(_token, _nativeAmount);
        } else {
            uint256 _amount = IERC20Upgradeable(_token).balanceOf(address(this));
            IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);
            emit RecoverTokens(_token, _amount);
        }
    }

    receive () external payable {}
}
