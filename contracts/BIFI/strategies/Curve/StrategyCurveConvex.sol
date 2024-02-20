// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/convex/IConvex.sol";
import "../../interfaces/curve/ICrvMinter.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../Common/BaseAllToNativeStrat.sol";

// Curve L1 strategy switchable between Curve and Convex
contract StrategyCurveConvex is BaseAllToNativeStrat {

    // this `pid` means we using Curve gauge and not Convex rewardPool
    uint constant public NO_PID = 42069;

    // Tokens used
    address public constant NATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IConvexBooster public constant booster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ICrvMinter public constant minter = ICrvMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);

    address public gauge; // curve gauge
    address public rewardPool; // convex base reward pool
    uint public pid; // convex booster poolId

    bool public isCrvMintable; // if CRV can be minted via Minter (gauge is added to Controller)
    bool public isCurveRewardsClaimable; // if extra rewards in curve gauge should be claimed
    bool public skipEarmarkRewards;

    function initialize(
        address _want,
        address _gauge,
        uint _pid,
        address _depositToken,
        address[] calldata _rewards,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        gauge = _gauge;
        pid = _pid;

        if (_pid != NO_PID) {
            (,,, rewardPool,,) = booster.poolInfo(_pid);
        }
        isCurveRewardsClaimable = true;

        __BaseStrategy_init(_want, NATIVE, _rewards, _commonAddresses);
        setDepositToken(_depositToken);
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
            booster.deposit(pid, amount, true);
        } else {
            IRewardsGauge(gauge).deposit(amount);
        }
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            if (rewardPool != address(0)) {
                IConvexRewardPool(rewardPool).withdrawAndUnwrap(amount, false);
            } else {
                IRewardsGauge(gauge).withdraw(amount);
            }
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        if (rewardPool != address(0)) {
            if (!skipEarmarkRewards && IConvexRewardPool(rewardPool).periodFinish() < block.timestamp) {
                booster.earmarkRewards(pid);
            }
            IConvexRewardPool(rewardPool).getReward();
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
        _approve(want, address(booster), amount);
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
            (,,,rewardPool,,) = booster.poolInfo(_pid);
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

    function setSkipEarmarkRewards(bool _skipEarmarkRewards) external onlyManager {
        skipEarmarkRewards = _skipEarmarkRewards;
    }

}
