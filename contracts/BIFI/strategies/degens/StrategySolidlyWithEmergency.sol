// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/merkl/IMerklClaimer.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

// Strategy for Gauges with emergency mode
contract StrategySolidlyWithEmergency is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IRewardPool public gauge;
    ISolidlyRouter public solidlyRouter;

    bool public stable;
    address public lpToken0;
    address public lpToken1;

    function initialize(
        address _gauge,
        address _solidlyRouter,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);

        gauge = IRewardPool(_gauge);
        solidlyRouter = ISolidlyRouter(_solidlyRouter);

        stable = ISolidlyPair(want).stable();
        lpToken0 = ISolidlyPair(want).token0();
        lpToken1 = ISolidlyPair(want).token1();
    }

    function stratName() public pure override returns (string memory) {
        return "SolidlyWithEmergency";
    }

    function balanceOfPool() public view override returns (uint) {
        return gauge.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(gauge), amount);
        gauge.deposit(amount);
    }

    function _withdraw(uint amount) internal override {
        gauge.withdraw(amount);
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        if (amount > 0) {
            if (gauge.emergency()) gauge.emergencyWithdraw();
            else gauge.withdraw(amount);
        }
    }

    function _claim() internal override {
        gauge.getReward();
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        address output = depositToken == address(0) ? native : depositToken;
        if (output != native) {
            _swap(native, output);
        }

        uint outputBal = IERC20(output).balanceOf(address(this));
        uint lp0Amt = outputBal / 2;
        uint lp1Amt = outputBal - lp0Amt;

        if (stable) {
            uint out0 = lpToken0 != output ? IBeefySwapper(swapper).getAmountOut(output, lpToken0, lp0Amt) : lp0Amt;
            uint out1 = lpToken1 != output ? IBeefySwapper(swapper).getAmountOut(output, lpToken1, lp1Amt) : lp1Amt;
            (uint amountA, uint amountB,) = solidlyRouter.quoteAddLiquidity(lpToken0, lpToken1, stable, out0, out1);
            uint ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = outputBal * 1e18 / (ratio + 1e18);
            lp1Amt = outputBal - lp0Amt;
        }

        _swap(output, lpToken0, lp0Amt);
        _swap(output, lpToken1, lp1Amt);

        uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IERC20(lpToken0).forceApprove(address(solidlyRouter), lp0Bal);
        IERC20(lpToken1).forceApprove(address(solidlyRouter), lp1Bal);
        solidlyRouter.addLiquidity(lpToken0, lpToken1, stable, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
    }

    function merklClaim(
        address claimer,
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        IMerklClaimer(claimer).claim(users, tokens, amounts, proofs);
    }
}
