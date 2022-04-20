// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/utils/math/SafeMath.sol";
import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/security/ReentrancyGuard.sol";

import "./ICakeV2Chef.sol";
import "./ICakePool.sol";
import "./CakeChefManager.sol";


contract VeCakeStaker is ERC20, ReentrancyGuard, CakeChefManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Addresses used
    IERC20 public want;
    ICakePool public veCake;

    // Duration of lock
    uint256 public constant DURATION = 31536000;

    // Our reserve integers 
    uint16 public constant MAX = 10000;
    uint256 public reserveRate;

    event DepositWant(uint256 tvl);
    event Withdraw(uint256 tvl);
    event RecoverTokens(address token, uint256 amount);
    event UpdatedReserveRate(uint256 newRate);

    constructor(
        address _want,
        address _veCake,
        address _keeper,
        uint256 _reserveRate,
        address _cakeBatch,
        uint256 _beCakeShare,
        string memory _name,
        string memory _symbol
    ) CakeChefManager(_keeper, _cakeBatch, _beCakeShare) ERC20(_name, _symbol) {
        want = IERC20(_want);
        veCake = ICakePool(_veCake);
        reserveRate = _reserveRate;

        want.safeApprove(address(veCake), type(uint256).max);
    }

    // helper function for depositing full balance of want
    function depositAll() external {
        _deposit(want.balanceOf(msg.sender));
    }

    // deposit an amount of want
    function deposit(uint256 _amount) external {
        _deposit(_amount);
    }

    // Deposits Cakes and mint beCake, harvests and checks for veCake deposit opportunities first.
    function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
        uint256 _pool = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfWant();
        _amount = _after.sub(_pool); // Additional check for deflationary tokens

        if (_amount > 0) {
            uint256 reserve = withdrawalReserve().add(rewardReserve());
            if (balanceOfWant() > reserve) {
                veCake.deposit(balanceOfWant().sub(reserve), DURATION);
            }

            _mint(msg.sender, _amount);
            emit DepositWant(totalCakes());
        }
    }

    // Withdraw capable if we have enough Cakes in the contract.
    function withdraw(uint256 _amount) public {
        require(_amount <= balanceOfWant(), "Not enough Cakes");
        _burn(msg.sender, _amount);
        want.safeTransfer(msg.sender, _amount);
        emit Withdraw(totalCakes());
    }

    // Our reserve Cakes held in the contract to enable withdraw capabilities
    function withdrawalReserve() public view returns (uint256 withdrawReserve) {
        // We calculate allocation for reserve of the total staked Cakes.
        withdrawReserve = balanceOfCakeInVe().mul(reserveRate).div(MAX);
    }

    // Extra Cakes are rewarded back to stakers
    function rewardReserve() public view returns (uint256 rewardReserve) {
        if (totalCakes < totalSupply()) {
            rewardReserve = 0;
        } else {
            rewardReserve = totalCakes().sub(totalSupply());
        }
    }

    // Send extra Cakes to cakeBatch if above withdrawal reserves
    function harvest() external {
        uint256 _cakeBal = balanceOfWant();
        uint256 _withdrawReserve = withdrawalReserve();

        if (_cakeBal > _withdrawReserve) {
            uint256 _rewards = _cakeBal.sub(_withdrawReserve);
            uint256 _rewardReserve = rewardReserve();

            // Don't send more than totalCakes
            if (_rewards > _rewardReserve) {
                _rewards = _rewardReserve;
            }
            want.safeTransfer(cakeBatch, _rewards);
        }
    }

    // Total Cakes in veCake contract and beCake contract.
    function totalCakes() public view returns (uint256) {
        return balanceOfWant().add(balanceOfCakeInVe());
    }

    // Calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // Calculate how much 'veWant' is held by this contract
    function balanceOfCakeInVe() public view returns (uint256) {
        (,,,,,,,,uint256 _amount) = veCake.userInfo(address(this));
        return _amount;
    }

    // Prevent any further 'want' deposits and remove approval
    function pause() public onlyManager {
        _pause();
        want.safeApprove(address(veCake), 0);
    }

    // allow 'want' deposits again and reinstate approval
    function unpause() external onlyManager {
        _unpause();
        want.safeApprove(address(veCake), type(uint256).max);
    }

    // panic beCake, pause deposits and withdraw Cakes from veCake
    function panic() external onlyManager {
        pause();
    }

    // can only be triggered once the lock is up
    function unlock() external onlyManager {
        uint256 cakeLocked = balanceOfCakeInVe();
        veCake.unlock(address(this));
        veCake.withdrawByAmount(cakeLocked);
    }

    // pass through a deposit to a boosted chef
    function deposit(address _cakeChef, uint256 _pid, uint256 _amount) external onlyWhitelist(_cakeChef, _pid) {
        // Grab needed pool info
        address _underlying = ICakeV2Chef(_cakeChef).lpToken(_pid);

        // Take before balances snapshot and transfer want from strat
        uint256 cakeBefore = balanceOfWant(); // How many Cake's the strategy holds
        IERC20(_underlying).safeTransferFrom(msg.sender, address(this), _amount);

        ICakeV2Chef(_cakeChef).deposit(_pid, _amount);
        uint256 cakeDiff = balanceOfWant().sub(cakeBefore); // Amount of Cakes the Chef sent us
        
        // Send beCake Batch their Cakes
        if (cakeDiff > 0) {
            uint256 batchCakes = cakeDiff.mul(beCakeShare).div(MAX);
            want.safeTransfer(cakeBatch, batchCakes);

            uint256 remaining = cakeDiff.sub(batchCakes);
            want.safeTransfer(msg.sender, remaining);
        }
    }

    // Pass through a withdrawal from boosted chef
    function withdraw(address _cakeChef, uint256 _pid, uint256 _amount) external onlyWhitelist(_cakeChef, _pid) {
        // Grab needed pool info
        address _underlying = ICakeV2Chef(_cakeChef).lpToken(_pid);

        uint256 cakeBefore = balanceOfWant(); // How many Cake's strategy the holds
        
        ICakeV2Chef(_cakeChef).withdraw(_pid, _amount);
        uint256 cakeDiff = balanceOfWant().sub(cakeBefore); // Amount of Cakes the Chef sent us
        IERC20(_underlying).safeTransfer(msg.sender, _amount);

        if (cakeDiff > 0) {
            // Send beCake Batch their Cakes
            uint256 batchCakes = cakeDiff.mul(beCakeShare).div(MAX);
            want.safeTransfer(cakeBatch, batchCakes);

            uint256 remaining = cakeDiff.sub(batchCakes);
            want.safeTransfer(msg.sender, remaining);
        }
    }

    // emergency withdraw losing all Cake rewards from boosted chef
    function emergencyWithdraw(address _cakeChef, uint256 _pid) external onlyWhitelist(_cakeChef, _pid) {
        address _underlying = ICakeV2Chef(_cakeChef).lpToken(_pid);
        uint256 _before = IERC20(_underlying).balanceOf(address(this));
        ICakeV2Chef(_cakeChef).emergencyWithdraw(_pid);
        uint256 _balance = IERC20(_underlying).balanceOf(address(this)).sub(_before);
        IERC20(_underlying).safeTransfer(msg.sender, _balance);
    }

    // Adjust reserve rate 
    function adjustReserve(uint256 _rate) external onlyOwner {
        require(_rate <= MAX, "Higher than max");
        reserveRate = _rate;
        emit UpdatedReserveRate(_rate);
    }

    function setVeCake(address _veCake) external onlyOwner {
        want.safeApprove(address(veCake), 0);
        veCake = ICakePool(_veCake);
        want.safeApprove(address(veCake), type(uint256).max);
    }

    // recover any tokens sent on error
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!token");

        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit RecoverTokens(_token, _amount);

    }
}
