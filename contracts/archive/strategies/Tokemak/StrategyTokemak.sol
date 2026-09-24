// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/tokemak/ITokemakVault.sol";
import "../../interfaces/tokemak/ITokemakRewarder.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/common/IERC20Extended.sol";

// Strategy for Tokemak
contract StrategyTokemak is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    // Tokens used
    ITokemakRewarder public rewarder;

    function initialize(
        address _rewarder,
        Addresses memory _commonAddresses
    ) external initializer {
        rewarder = ITokemakRewarder(_rewarder);
        _commonAddresses.want = rewarder.stakingToken();
        _commonAddresses.depositToken = ITokemakVault(_commonAddresses.want).asset();
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = rewarder.rewardToken();

        __BaseStrategy_init(_commonAddresses, rewardTokens);
    }

    function stratName() public pure override returns (string memory) {
        return "Tokemak";
    }

    function balanceOfPool() public view override returns (uint) {
        return rewarder.balanceOf(address(this));
    }

    function _deposit(uint _amount) internal override {
        if (_amount > 0) {
            IERC20(want).forceApprove(address(rewarder), _amount);
            rewarder.stake(address(this), _amount);
        }
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

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        _swap(native, depositToken);
        uint256 bal = IERC20(depositToken).balanceOf(address(this));
        IERC20(depositToken).forceApprove(want, bal);
        ITokemakVault(want).deposit(bal, address(this));
    }
}
