// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/convex/IConvex.sol";
import "../../interfaces/curve/ICrvMinter.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../Common/BaseAllToNativeStrat.sol";

// Curve L2 strategy switchable between Curve and Convex
contract StrategyCurveConvexL2 is BaseAllToNativeStrat {
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
        address _native,
        address _want,
        address _gauge,
        uint _pid,
        address _depositToken,
        address[] calldata _rewards,
        CommonAddresses calldata _commonAddresses
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
        __BaseStrategy_init(_want, _native, _rewards, _commonAddresses);
        setDepositToken(_depositToken);
        setHarvestOnDeposit(true);
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
            booster.deposit(pid, amount);
        } else {
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

    function _giveAllowances() internal override {
        uint amount = type(uint).max;
        _approve(want, address(gauge), amount);
        if (pid != NO_PID) _approve(want, address(booster), type(uint).max);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal override {
        _approve(want, address(gauge), 0);
        _approve(want, address(booster), 0);
        _approve(native, unirouter, 0);
    }

    function setConvexPid(uint _pid) external onlyOwner {
        _withdraw(balanceOfPool());
        if (_pid != NO_PID) {
            (,,rewardPool,,) = booster.poolInfo(_pid);
            if (IERC20(want).allowance(address(this), address(booster)) == 0) {
                _approve(want, address(booster), type(uint).max);
            }
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
