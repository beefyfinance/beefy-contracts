// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/convex/IStakedCvx.sol";
import "../Common/BaseAllToNativeStrat.sol";

// CVX single staking
contract StrategyConvexCVX is BaseAllToNativeStrat {

    // Tokens used
    address public constant NATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    IStakedCvx public constant staking = IStakedCvx(0xCF50b810E57Ac33B91dCF525C6ddd9881B139332);

    bool public claimExtras;

    function initialize(address[] calldata _rewards, CommonAddresses calldata _commonAddresses) public initializer {
        __BaseStrategy_init(CVX, NATIVE, _rewards, _commonAddresses);
    }

    function balanceOfPool() public view override returns (uint) {
        return staking.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        staking.stake(amount);
    }

    function _withdraw(uint amount) internal override {
        staking.withdraw(amount, false);
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        if (amount > 0) {
            staking.withdraw(amount, false);
        }
    }

    function _claim() internal override {
        staking.getReward(address(this), claimExtras, false);
    }

    function _verifyRewardToken(address token) internal view override {}

    function _giveAllowances() internal override {
        uint amount = type(uint).max;
        _approve(want, address(staking), amount);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal override {
        _approve(want, address(staking), 0);
        _approve(native, unirouter, 0);
    }

    function setClaimExtras(bool _claimExtras) external onlyManager {
        claimExtras = _claimExtras;
    }
}
