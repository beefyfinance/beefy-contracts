// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/tokemak/ITokemakVault.sol";
import "../../interfaces/tokemak/ITokemakRewarder.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/common/IERC20Extended.sol";

// Strategy for Tokemak
contract StrategyTokemak is BaseAllToNativeFactoryStrat {

    // Tokens used
    ITokemakRewarder public rewarder;
    address public underlying;

    function initialize(
        address _rewarder,
        address[] calldata _rewards,
        Addresses calldata _commonAddresses
    ) public initializer {
        rewarder = ITokemakRewarder(_rewarder);
        underlying = ITokemakVault(_commonAddresses.want).asset();

        __BaseStrategy_init(_commonAddresses, _rewards);
        _giveAllowances();
    }

    function balanceOfPool() public view override returns (uint) {
        return rewarder.balanceOf(address(this));
    }

    function stratName() public pure override returns (string memory) {
        return "Tokemak";
    }

    function _deposit(uint _amount) internal override {
        if (_amount > 0) rewarder.stake(address(this), _amount);
    }

    function _withdraw(uint _amount) internal override {
        if (_amount > 0) rewarder.withdraw(address(this), _amount, false);
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        rewarder.getReward();
    }

    function _swapNativeToWant() internal override {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (underlying != native) IBeefySwapper(swapper).swap(native, underlying, nativeBal);
        uint256 underlyingBal = IERC20(underlying).balanceOf(address(this));
        ITokemakVault(want).deposit(underlyingBal, address(this));
    }

    function _giveAllowances() internal {
        uint max = type(uint).max;
        _approve(want, address(rewarder), max);
        _approve(native, address(swapper), max);

        _approve(underlying, address(want), 0);
        _approve(underlying, address(want), max);
    }

    function _removeAllowances() internal {
        _approve(want, address(rewarder), 0);
        _approve(native, address(swapper), 0);
        _approve(underlying, address(want), 0);
    }

    function panic() public override onlyManager {
        pause();
        _emergencyWithdraw();
        _removeAllowances();
    }

    function pause() public override onlyManager {
        _pause();
        _removeAllowances();
    }

    function unpause() external override onlyManager {
        _unpause();
        _giveAllowances();
        deposit();
    }


    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).approve(_spender, amount);
    }

    function _verifyRewardToken(address token) internal view override {}
}
