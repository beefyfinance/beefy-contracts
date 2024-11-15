// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/interfaces/IERC4626.sol";

import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/beefy/IBeefyRewardPool.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyNum is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public want;
    address public reward;

    // Other addresses
    address public rewardPool;

    uint256 public duration;
    uint256 public storedRate;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);
    event SetReward(address reward);
    event SetDuration(uint256 duration);

    function initialize(
        address _want,
        address _native,
        address _reward,
        address _rewardPool,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StratFeeManager_init(_commonAddresses);

        want = _want;
        native = _native;
        reward = _reward;
        rewardPool = _rewardPool;

        duration = 1 days;
        storedRate = IERC4626(want).convertToAssets(1e18);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256 rate = IERC4626(want).convertToAssets(1e18);
        uint256 wantBal = balanceOfWant();
        if (rate > storedRate) {
            uint256 skim = wantBal * ( 1e18 - ( storedRate * 1e18 / rate ) ) / 1e18;
            storedRate = rate;

            skim = chargeFees(callFeeRecipient, skim);
            _notifyReward(skim);

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, 0, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient, uint256 _amount) internal returns (uint256 skim) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 fee = _amount * fees.total / DIVISOR;
        skim = _amount - fee;
        IBeefySwapper(unirouter).swap(want, native, fee);
        uint256 feeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = feeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = feeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = feeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function _notifyReward(uint256 _amount) internal {
        IBeefySwapper(unirouter).swap(want, reward, _amount);
        uint256 rewardBal = IERC20(reward).balanceOf(address(this)) / duration * duration;
        if (rewardBal > 0) IBeefyRewardPool(rewardPool).notifyRewardAmount(reward, rewardBal, duration);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public pure returns (uint256) {
        return 0;
    }

    // returns rewards unharvested
    function rewardsAvailable() public pure returns (uint256) {
        return 0;
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            super.setWithdrawalFee(0);
        } else {
            super.setWithdrawalFee(10);
        }
    }

    function setReward(address _reward) external onlyManager {
        require(_reward != want, "reward!=want");
        IERC20(reward).safeApprove(rewardPool, 0);
        reward = _reward;
        if (!paused()) IERC20(reward).safeApprove(rewardPool, type(uint256).max);
        emit SetReward(_reward);
    }

    function setDuration(uint256 _duration) external onlyManager {
        require(_duration != 0, "duration!=0");
        duration = _duration;
        emit SetDuration(_duration);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(unirouter, type(uint256).max);
        IERC20(reward).safeApprove(rewardPool, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(unirouter, 0);
        IERC20(reward).safeApprove(rewardPool, 0);
    }
}