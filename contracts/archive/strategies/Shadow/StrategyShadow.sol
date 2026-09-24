// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/shadow/IxShadow.sol";
import "../../interfaces/shadow/Ix33.sol";
import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/ISolidlyGauge.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

contract StrategyShadow is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    ISolidlyGauge public gauge;
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

        gauge = ISolidlyGauge(_gauge);
        solidlyRouter = ISolidlyRouter(_solidlyRouter);

        stable = ISolidlyPair(want).stable();
        lpToken0 = ISolidlyPair(want).token0();
        lpToken1 = ISolidlyPair(want).token1();
    }

    function stratName() public pure override returns (string memory) {
        return "Shadow";
    }

    function balanceOfPool() public view override returns (uint) {
        return gauge.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(gauge), amount);
        gauge.deposit(amount);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) gauge.withdraw(amount);
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        gauge.getReward(address(this), rewards);

        // Exit xShadow
        address xShadow = 0x5050bc082FF4A74Fb6B0B04385dEfdDB114b2424;
        address shadow = 0x3333b97138D4b086720b5aE8A7844b1345a33333;
        address x33 = 0x3333111A391cC08fa51353E9195526A70b333333;
        address adapter = 0x9710E10A8f6FbA8C391606fee18614885684548d;

        uint256 xShadowBalance = IERC20(xShadow).balanceOf(address(this));
        if (xShadowBalance > 0) {
            uint256 shares = Ix33(x33).convertToShares(xShadowBalance);
            uint256 amountOut = IBeefySwapper(swapper).getAmountOut(x33, shadow, shares);

            if (amountOut > (xShadowBalance / 2)) {
                IERC20(xShadow).forceApprove(adapter, xShadowBalance);
                Ix33(adapter).deposit(xShadowBalance, address(this));
                shares = IERC20(x33).balanceOf(address(this));
                IERC20(x33).forceApprove(swapper, shares);
                IBeefySwapper(swapper).swap(x33, native, shares);
            } else {
                IxShadow(xShadow).exit(xShadowBalance);
                uint256 shadowBalance = IERC20(shadow).balanceOf(address(this));
                IERC20(shadow).forceApprove(swapper, shadowBalance);
                IBeefySwapper(swapper).swap(shadow, native, shadowBalance);
            }
        }
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        uint256 lp0Amt = nativeBal / 2;
        uint256 lp1Amt = nativeBal - lp0Amt;

        if (stable) {
            uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
            uint256 out0 = IBeefySwapper(swapper).getAmountOut(native, lpToken0, lp0Amt) * 1e18 / lp0Decimals;
            uint256 out1 = IBeefySwapper(swapper).getAmountOut(native, lpToken1, lp1Amt) * 1e18 / lp1Decimals;
            (uint256 amountA, uint256 amountB,) = solidlyRouter.quoteAddLiquidity(lpToken0, lpToken1, stable, out0, out1);
            amountA = amountA * 1e18 / lp0Decimals;
            amountB = amountB * 1e18 / lp1Decimals;
            uint256 ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = nativeBal * 1e18 / (ratio + 1e18);
            lp1Amt = nativeBal - lp0Amt;
        }

        if (lpToken0 != native) {
            IERC20(native).forceApprove(swapper, lp0Amt);
            IBeefySwapper(swapper).swap(native, lpToken0, lp0Amt);
        }

        if (lpToken1 != native) {
            IERC20(native).forceApprove(swapper, lp1Amt);
            IBeefySwapper(swapper).swap(native, lpToken1, lp1Amt);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IERC20(lpToken0).forceApprove(address(solidlyRouter), lp0Bal);
        IERC20(lpToken1).forceApprove(address(solidlyRouter), lp1Bal);
        solidlyRouter.addLiquidity(lpToken0, lpToken1, stable, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
    }

    function setGauge(address _gauge) external onlyOwner {
        require(_gauge != address(0), "Gauge cannot be 0 address");
        _emergencyWithdraw();
        gauge = ISolidlyGauge(_gauge);
        if (!(paused() || factory.globalPause() || factory.strategyPause(stratName()))) deposit();
    }
}
