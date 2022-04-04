// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./IJoeChef.sol";
import "./IVeJoe.sol";
import "./ChefManager.sol";

contract VeJoeStaker is ERC20Upgradeable, ReentrancyGuardUpgradeable, ChefManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    // Addresses used
    IERC20Upgradeable public want;
    IVeJoe public veJoe;

    // Our reserve integers 
    uint256 public constant MAX = 1000;
    uint256 public reserveRate; 

    event DepositWant(uint256 tvl);
    event Withdraw(uint256 tvl);
    event RecoverTokens(address token, uint256 amount);
    event UpdatedReserveRate(uint256 newRate);

    function initialize(
        address _veJoe,
        address _keeper,
        address _rewardPool,
        address _joeChef,
        uint256 _reserveRate,
        string memory _name,
        string memory _symbol
    ) public initializer {
        managerInitialize(_joeChef, _keeper, _rewardPool);
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
        require(_amount > balanceOfWant(), "Not enough Joes to withdraw");
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
            harvestVeJoe();
        }
    }

    // claim the veJoes
    function harvestVeJoe() public {
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
        (address _underlying,,,,,,,,) = joeChef.poolInfo(_pid);
        uint256 joeBefore = balanceOfWant(); // How many Joe's strategy holds
        IERC20Upgradeable(_underlying).safeTransferFrom(msg.sender, address(this), _amount);
        joeChef.deposit(_pid, _amount);
        uint256 joeDiff = balanceOfWant().sub(joeBefore); // Amount of Joes the Chef sent us
        want.safeTransfer(msg.sender, joeDiff); 
    }

    // pass through a withdrawal from boosted chef
    function withdraw(uint256 _pid, uint256 _amount) external onlyWhitelist(_pid) {
        (address _underlying,,,,,,,,) = joeChef.poolInfo(_pid);
        uint256 joeBefore = balanceOfWant(); // How many Joe's strategy holds
        joeChef.withdraw(_pid, _amount);
        uint256 joeDiff = balanceOfWant().sub(joeBefore); // Amount of Joes the Chef sent us
        IERC20Upgradeable(_underlying).safeTransfer(msg.sender, _amount);
        want.safeTransfer(msg.sender, joeDiff); 
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

    // recover any unknown tokens
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!token");

        uint256 _amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);

        emit RecoverTokens(_token, _amount);
    }
}
