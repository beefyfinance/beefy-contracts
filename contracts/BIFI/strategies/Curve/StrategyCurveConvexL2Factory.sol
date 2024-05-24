// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/convex/IConvex.sol";
import "../../interfaces/curve/ICrvMinter.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

// Curve L2 strategy switchable between Curve and Convex
contract StrategyCurveConvexL2Factory is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    // this `pid` means we using Curve gauge and not Convex rewardPool
    uint constant public NO_PID = 42069;

    IConvexBoosterL2 public constant booster = IConvexBoosterL2(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ICrvMinter public constant minter = ICrvMinter(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

    address public gauge; // curve gauge
    address public rewardPool; // convex base reward pool
    uint public pid; // convex booster poolId

    bool public isCrvMintable; // if CRV can be minted via Minter (gauge is added to Controller)
    bool public isCurveRewardsClaimable; // if extra rewards in curve gauge should be claimed

    function initialize(
        address _gauge,
        uint _pid,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        gauge = _gauge;
        pid = _pid;

        if (_rewards.length > 1) {
            isCurveRewardsClaimable = true;
        }
        if (_pid != NO_PID) {
            (,,rewardPool,,) = booster.poolInfo(_pid);
        } else {
            isCrvMintable = true;
        }
        __BaseStrategy_init(_addresses, _rewards);
        setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "CurveConvexL2_v1";
    }

    function balanceOfPool() public view override returns (uint) {
        if (rewardPool != address(0)) {
            return IConvexRewardPool(rewardPool).balanceOf(address(this));
        } else {
            return IRewardsGauge(gauge).balanceOf(address(this));
        }
    }

    function _deposit(uint amount) internal override {
        if (rewardPool != address(0)) {
            IERC20(want).forceApprove(address(booster), amount);
            booster.deposit(pid, amount);
        } else {
            IERC20(want).forceApprove(gauge, amount);
            IRewardsGauge(gauge).deposit(amount);
        }
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            if (rewardPool != address(0)) {
                IConvexRewardPool(rewardPool).withdraw(amount, false);
            } else {
                IRewardsGauge(gauge).withdraw(amount);
            }
        }
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        if (amount > 0) {
            if (rewardPool != address(0)) {
                IConvexRewardPool(rewardPool).emergencyWithdraw(amount);
            } else {
                IRewardsGauge(gauge).withdraw(amount);
            }
        }
    }

    function _claim() internal override {
        if (rewardPool != address(0)) {
            IConvexRewardPool(rewardPool).getReward(address(this));
        } else {
            if (isCrvMintable) minter.mint(gauge);
            if (isCurveRewardsClaimable) IRewardsGauge(gauge).claim_rewards(address(this));
        }
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != gauge, "!gauge");
        require(token != rewardPool, "!rewardPool");
    }

    function setConvexPid(uint _pid) external onlyOwner {
        _withdraw(balanceOfPool());
        if (_pid != NO_PID) {
            (,,rewardPool,,) = booster.poolInfo(_pid);
        } else {
            rewardPool = address(0);
        }
        pid = _pid;
        deposit();
    }

    function setCrvMintable(bool _isCrvMintable) external onlyManager {
        isCrvMintable = _isCrvMintable;
    }

    function setCurveRewardsClaimable(bool _isCurveRewardsClaimable) external onlyManager {
        isCurveRewardsClaimable = _isCurveRewardsClaimable;
    }

}
