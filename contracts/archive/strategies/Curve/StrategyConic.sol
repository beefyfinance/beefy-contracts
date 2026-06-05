// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/curve/IConic.sol";
import "../Common/BaseAllToNativeStrat.sol";

contract StrategyConic is BaseAllToNativeStrat {

    // Tokens used
    address public constant NATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    ILpTokenStaker public constant lpStaker = ILpTokenStaker(0xA5241560306298efb9ed80b87427e664FFff0CF9);

    address public conicPool; // conic omnipool
    IRewardManager public rewardManager;

    function initialize(
        address _want,
        address _depositToken,
        address[] calldata _rewards,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        want = _want;
        conicPool = ILpToken(_want).minter();
        rewardManager = IConicPool(conicPool).rewardManager();

        __BaseStrategy_init(_want, NATIVE, _rewards, _commonAddresses);
        setDepositToken(_depositToken);
    }

    function balanceOfPool() public view override returns (uint) {
        return lpStaker.getUserBalanceForPool(conicPool, address(this));
    }

    function _deposit(uint amount) internal override {
        lpStaker.stake(amount, conicPool);
    }

    function _withdraw(uint amount) internal override {
        lpStaker.unstake(amount, conicPool);
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        lpStaker.unstake(amount, conicPool);
    }

    function _claim() internal override {
        rewardManager.claimEarnings();
    }

    function _verifyRewardToken(address token) internal view override {}

    function _giveAllowances() internal override {
        uint amount = type(uint).max;
        _approve(want, address(lpStaker), amount);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal override {
        _approve(want, address(lpStaker), 0);
        _approve(native, unirouter, 0);
    }
}
