// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

contract StrategyPearlV1 is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IRewardPool public gauge;
    address public unirouter;
    address public lpToken0;
    address public lpToken1;
    bool public stable;

    function initialize(
        IRewardPool _gauge,
        address _unirouter,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer  {
        __BaseStrategy_init(_addresses, _rewards);
        gauge = _gauge;
        unirouter = _unirouter;
        lpToken0 = ISolidlyPair(want).token0();
        lpToken1 = ISolidlyPair(want).token1();
        stable = ISolidlyPair(want).stable();
        setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "PearlV1";
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
            gauge.withdraw(amount);
        }
    }

    function _claim() internal override {
        gauge.getReward();
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        uint256 outputBal = IERC20(native).balanceOf(address(this));
        uint256 lp0Amt = outputBal / 2;
        uint256 lp1Amt = outputBal - lp0Amt;

        if (stable) {
            uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();

            uint out0 = 1e18;
            uint out1 = ISolidlyPair(want).getAmountOut(lp0Decimals, lpToken0) * 1e18 / lp1Decimals;
            (uint256 amountA, uint256 amountB,) = ISolidlyRouter(unirouter).quoteAddLiquidity(lpToken0, lpToken1, stable, out0, out1);
            amountA = amountA * 1e18 / lp0Decimals;
            amountB = amountB * 1e18 / lp1Decimals;
            uint256 ratio = out0 * 1e18 / out1 * amountB / amountA;

            lp0Amt = outputBal * 1e18 / (ratio + 1e18);
            lp1Amt = outputBal - lp0Amt;
        }

        if (lpToken0 != native) {
            _swap(native, lpToken0, lp0Amt);
        }
        if (lpToken1 != native) {
            _swap(native, lpToken1, lp1Amt);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IERC20(lpToken0).forceApprove(unirouter, lp0Bal);
        IERC20(lpToken1).forceApprove(unirouter, lp1Bal);
        ISolidlyRouter(unirouter).addLiquidity(lpToken0, lpToken1, stable, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
    }
}