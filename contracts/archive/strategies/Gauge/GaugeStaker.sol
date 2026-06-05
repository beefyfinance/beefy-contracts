// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../../interfaces/common/gauge/IVeWant.sol";
import "./GaugeManager.sol";

contract GaugeStaker is ERC20Upgradeable, ReentrancyGuardUpgradeable, GaugeManager {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    // Tokens used
    IERC20Upgradeable public want;
    IVeWant public veWant;

    uint256 private constant MAXTIME = 4 * 364 * 86400;
    uint256 private constant WEEK = 7 * 86400;

    event DepositWant(uint256 tvl);
    event Vote(address[] tokenVote, uint256[] weights);
    event RecoverTokens(address token, uint256 amount);

    function initialize(
        address _veWant,
        address _feeDistributor,
        address _gaugeProxy,
        address _keeper,
        address _rewardPool,
        string memory _name,
        string memory _symbol
    ) public initializer {
        managerInitialize(_feeDistributor, _gaugeProxy, _keeper, _rewardPool);
        veWant = IVeWant(_veWant);
        want = IERC20Upgradeable(veWant.token());

        __ERC20_init(_name, _symbol);

        want.safeApprove(address(veWant), type(uint256).max);
    }

    // vote on boosted farms
    function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external onlyManager {
        gaugeProxy.vote(_tokenVote, _weights);
        emit Vote(_tokenVote, _weights);
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

    // deposit 'want' and lock
    function _deposit(address _user, uint256 _amount) internal nonReentrant whenNotPaused {
        uint256 _pool = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = balanceOfWant();
        _amount = _after.sub(_pool); // Additional check for deflationary tokens
        if (_amount > 0) {
            if (balanceOfVe() > 0) {
                increaseUnlockTime();
                veWant.increase_amount(_amount);
            } else {
                _createLock();
            }
            _mint(_user, _amount);
            emit DepositWant(balanceOfVe());
        }
    }

    // increase the lock period
    function increaseUnlockTime() public {
        uint256 _newUnlockTime = newUnlockTime();
        if (_newUnlockTime > currentUnlockTime()) {
            veWant.increase_unlock_time(_newUnlockTime);
        }
    }

    // create a new lock
    function _createLock() internal {
        veWant.withdraw();
        veWant.create_lock(balanceOfWant(), newUnlockTime());
    }

    // timestamp at which 'want' is unlocked
    function currentUnlockTime() public view returns (uint256) {
        return veWant.locked__end(address(this));
    }

    // new unlock timestamp rounded down to start of the week
    function newUnlockTime() internal view returns (uint256) {
        return block.timestamp.add(MAXTIME).div(WEEK).mul(WEEK);
    }

    // calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // calculate how much 'veWant' is held by this contract
    function balanceOfVe() public view returns (uint256) {
        return veWant.balanceOf(address(this));
    }

    // prevent any further 'want' deposits and remove approval
    function pause() public onlyManager {
        _pause();
        want.safeApprove(address(veWant), 0);
    }

    // allow 'want' deposits again and reinstate approval
    function unpause() external onlyManager {
        _unpause();
        want.safeApprove(address(veWant), type(uint256).max);
    }

    // pass through a deposit to a gauge
    function deposit(address _gauge, uint256 _amount) external onlyWhitelist(_gauge) {
        address _underlying = IGauge(_gauge).TOKEN();
        IERC20Upgradeable(_underlying).safeTransferFrom(msg.sender, address(this), _amount);
        IGauge(_gauge).deposit(_amount);
    }

    // pass through a withdrawal from a gauge
    function withdraw(address _gauge, uint256 _amount) external onlyWhitelist(_gauge) {
        address _underlying = IGauge(_gauge).TOKEN();
        IGauge(_gauge).withdraw(_amount);
        IERC20Upgradeable(_underlying).safeTransfer(msg.sender, _amount);
    }

    // pass through a full withdrawal from a gauge
    function withdrawAll(address _gauge) external onlyWhitelist(_gauge) {
        address _underlying = IGauge(_gauge).TOKEN();
        uint256 _before = IERC20Upgradeable(_underlying).balanceOf(address(this));
        IGauge(_gauge).withdrawAll();
        uint256 _balance = IERC20Upgradeable(_underlying).balanceOf(address(this)).sub(_before);
        IERC20Upgradeable(_underlying).safeTransfer(msg.sender, _balance);
    }

    // pass through rewards from a gauge
    function claimGaugeReward(address _gauge) external onlyWhitelist(_gauge) {
        uint256 _before = balanceOfWant();
        IGauge(_gauge).getReward();
        uint256 _balance = balanceOfWant().sub(_before);
        want.safeTransfer(msg.sender, _balance);
    }

    // pass through rewards from the fee distributor
    function claimVeWantReward() external onlyRewardPool {
        uint256 _before = balanceOfWant();
        feeDistributor.claim();
        uint256 _balance = balanceOfWant().sub(_before);
        want.safeTransfer(msg.sender, _balance);
    }

    // recover any unknown tokens
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want), "!token");

        uint256 _amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(msg.sender, _amount);

        emit RecoverTokens(_token, _amount);
    }
}
