// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Common/BaseAllToNativeFactoryStrat.sol";
import "../../interfaces/common/IRewardPool.sol";
import "./IEqb.sol";
import "./IPendle.sol";

contract StrategyEquilibria is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    // this `pid` means we using Pendle directly and not Equilibria rewardPool
    uint constant public NO_PID = 42069;

    IEqbBooster public booster;
    IRewardPool public rewardPool;
    IXEqb public xEqb;
    uint256 public pid;
    uint public lastEqbRedeem;
    uint public redeemDelay;
    bool public redeemEqb;

    function initialize(
        IEqbBooster _booster,
        uint _pid,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer  {
        xEqb = IXEqb(_booster.xEqb());
        booster = _booster;
        pid = _pid;
        redeemEqb = false;
        redeemDelay = 1 days;

        if (_pid != NO_PID) {
            (,,address _rewardPool) = _booster.poolInfo(_pid);
            rewardPool = IRewardPool(_rewardPool);
        } else {
            IPendleMarket(_addresses.want).redeemRewards(address(this));
        }

        __BaseStrategy_init(_addresses, _rewards);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function _isEquilibria() internal view returns (bool) {
        return address(rewardPool) != address(0);
    }

    function stratName() public pure override returns (string memory) {
        return "EquilibriaPendle";
    }

    function balanceOfPool() public view override returns (uint) {
        if (_isEquilibria()) {
            return rewardPool.balanceOf(address(this));
        }
        return 0;
    }

    function _deposit(uint amount) internal override {
        if (_isEquilibria()) {
            IERC20(want).forceApprove(address(booster), amount);
            booster.deposit(pid, amount, true);
        }
    }

    function _withdraw(uint amount) internal override {
        if (_isEquilibria() && amount > 0) {
            rewardPool.withdraw(amount);
            booster.withdraw(pid, amount);
        }
    }

    function _emergencyWithdraw() internal override {
        if (_isEquilibria() && rewardPool.balanceOf(address(this)) > 0) {
            rewardPool.emergencyWithdraw();
            booster.withdrawAll(pid);
        }
    }

    function _claim() internal override {
        if (_isEquilibria()) {
            rewardPool.getReward(address(this));
        } else {
            IPendleMarket(want).redeemRewards(address(this));
        }

        if (redeemEqb) {
            uint len = xEqb.getUserRedeemsLength(address(this));
            for (uint i; i < len; ++i) {
                (,,uint256 endTime) = xEqb.getUserRedeem(address(this), i);
                if (endTime <= block.timestamp) {
                    xEqb.finalizeRedeem(i);
                    break;
                }
            }
            if (lastEqbRedeem + redeemDelay < block.timestamp && xEqb.balanceOf(address(this)) > 0) {
                _redeemAllXEqb();
                lastEqbRedeem = block.timestamp;
            }
        }
    }

    function _verifyRewardToken(address token) internal view override {
        if (_isEquilibria()) {
            require(token != rewardPool.stakingToken(), "!stakingToken");
        }
    }

    function setEqbPid(uint _pid, bool claim) public onlyManager {
        if (pid == _pid) return;

        _withdraw(balanceOfPool());
        if (claim) _claim();

        if (_pid != NO_PID) {
            (address _market,,address _rewardPool) = booster.poolInfo(_pid);
            require(want == _market, "!market");
            rewardPool = IRewardPool(_rewardPool);
        } else {
            rewardPool = IRewardPool(address(0));
        }
        pid = _pid;
        deposit();
    }

    function setRedeemEqb(bool doRedeem, uint delay) external onlyManager {
        redeemEqb = doRedeem;
        redeemDelay = delay;
    }

    function redeem(uint amount, uint duration) external onlyManager {
        xEqb.redeem(amount, duration);
    }

    function redeemAll() external onlyManager {
        _redeemAllXEqb();
    }

    function _redeemAllXEqb() internal {
        xEqb.redeem(xEqb.balanceOf(address(this)), xEqb.minRedeemDuration());
    }

    function finalizeRedeem(uint redeemIndex) external onlyManager {
        xEqb.finalizeRedeem(redeemIndex);
    }

    // in case we get eqbLPs here
    function boosterWithdrawAll() external onlyManager {
        booster.withdrawAll(pid);
    }

}