// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/convex/IStaking.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

contract StrategyConvexStakingFraxtal is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IStaking public staking;

    function initialize(
        address _staking,
        address[] calldata _rewards,
        address delegationRegistry,
        address initialDelegate,
        Addresses calldata _addresses
    ) public initializer {
        staking = IStaking(_staking);
        __BaseStrategy_init(_addresses, _rewards);
        setHarvestOnDeposit(true);

        if (delegationRegistry != address(0)) {
            bool res;
            (res,) = delegationRegistry.call(abi.encodeWithSignature("setDelegationForSelf(address)", initialDelegate));
            (res,) = delegationRegistry.call(abi.encodeWithSignature("disableSelfManagingDelegations()"));
        }
    }

    function stratName() public pure override returns (string memory) {
        return "ConvexStaking";
    }

    function balanceOfPool() public view override returns (uint) {
        return staking.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(staking), amount);
        staking.stakeFor(address(this), amount);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            staking.withdraw(amount, false);
        }
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        if (amount > 0) {
            staking.emergencyWithdraw(amount);
        }
    }

    function _claim() internal override {
        staking.getReward(address(this));
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != address(staking), "!staking");
    }

}
