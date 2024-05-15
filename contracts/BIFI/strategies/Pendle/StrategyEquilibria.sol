// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Common/BaseAllToNativeFactoryStrat.sol";
import "../../interfaces/common/IRewardPool.sol";
import "./IEqb.sol";

contract StrategyEquilibria is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

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
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer  {
        (,,address _rewardPool) = _booster.poolInfo(_pid);
        rewardPool = IRewardPool(_rewardPool);
        xEqb = IXEqb(_booster.xEqb());
        booster = _booster;
        pid = _pid;
        redeemEqb = true;
        redeemDelay = 1 days;

        __BaseStrategy_init(_addresses, _rewards);
        setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "Equilibria_v1";
    }

    function balanceOfPool() public view override returns (uint) {
        return rewardPool.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(booster), amount);
        booster.deposit(pid, amount, true);
    }

    function _withdraw(uint amount) internal override {
        rewardPool.withdraw(amount);
        booster.withdraw(pid, amount);
    }

    function _emergencyWithdraw() internal override {
        if (rewardPool.balanceOf(address(this)) > 0) {
            rewardPool.emergencyWithdraw();
            booster.withdrawAll(pid);
        }
    }

    function _claim() internal override {
        rewardPool.getReward(address(this));

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
        require(token != rewardPool.stakingToken(), "!stakingToken");
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