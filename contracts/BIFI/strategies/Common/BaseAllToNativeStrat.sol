// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../Common/StratFeeManagerInitializable.sol";

abstract contract BaseAllToNativeStrat is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    struct Reward {
        address token;
        uint minAmount; // minimum amount to be swapped to native
    }
    Reward[] public rewards;

    address public want;
    address public native;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public lockDuration;
    bool public harvestOnDeposit;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function __BaseStrategy_init(address _want, address _native, Reward[] calldata _rewards, CommonAddresses calldata _commonAddresses) internal onlyInitializing {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        native = _native;

        for (uint i; i < _rewards.length; i++) {
            addReward(_rewards[i].token, _rewards[i].minAmount);
        }

        lockDuration = 1 days;
        setWithdrawalFee(0);
        _giveAllowances();
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view virtual returns (uint);
    function _deposit(uint amount) internal virtual;
    function _withdraw(uint amount) internal virtual;
    function _emergencyWithdraw() internal virtual;
    function _claim() internal virtual;
    function _swapNativeToWant() internal virtual;
    function _verifyRewardToken(address token) internal view virtual;
    function _giveAllowances() internal virtual;
    function _removeAllowances() internal virtual;

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            _deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            _withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }

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
            _harvest(tx.origin, true);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin, false);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient, false);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient, bool onDeposit) internal whenNotPaused {
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            _chargeFees(callFeeRecipient);
            _swapNativeToWant();
            uint256 wantHarvested = balanceOfWant();
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;

            if (!onDeposit) {
                deposit();
            }

            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapRewardsToNative() internal virtual {
        for (uint i; i < rewards.length; ++i) {
            address token = rewards[i].token;
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > rewards[i].minAmount) {
                IBeefySwapper(unirouter).swap(token, native, amount);
            }
        }
    }

    // performance fees
    function _chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function addReward(address _token, uint _minAmount) public onlyManager {
        require(_token != want, "!want");
        require(_token != native, "!native");
        _verifyRewardToken(_token);

        rewards.push(Reward(_token, _minAmount));
        _approve(_token, unirouter, 0);
        _approve(_token, unirouter, type(uint).max);
    }

    function removeReward(uint i) external onlyManager {
        rewards[i] = rewards[rewards.length - 1];
        rewards.pop();
    }

    function resetRewards() external onlyManager {
        for (uint i; i < rewards.length; ++i) {
            _approve(rewards[i].token, unirouter, 0);
        }
        delete rewards;
    }

    function lockedProfit() public view returns (uint256) {
        if (lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < lockDuration ? lockDuration - elapsed : 0;
        return totalLocked * remaining / lockDuration;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            lockDuration = 0;
        } else {
            lockDuration = 1 days;
        }
    }

    function setLockDuration(uint _duration) external onlyManager {
        lockDuration = _duration;
    }

    function rewardsAvailable() external view virtual returns (uint) {
        return 0;
    }

    function callReward() external view virtual returns (uint) {
        return 0;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _emergencyWithdraw();
        IERC20(want).transfer(vault, balanceOfWant());
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        _emergencyWithdraw();
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

    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).approve(_spender, amount);
    }
}