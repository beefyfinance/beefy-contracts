// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/equalizer/IEqualizerRewardPool.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/common/IERC20Extended.sol";

// Strategy for dealing with equalizer
contract StrategyEqualizerFactory is BaseAllToNativeFactoryStrat {

    // Tokens used
    IEqualizerRewardPool public rewardPool; // reward pool
    ISolidlyRouter public solidlyRouter;
    address public lpToken0;
    address public lpToken1;

    function initialize(
        address _rewardPool,
        address _solidlyRouter,
        address[] calldata _rewards,
        Addresses calldata _commonAddresses
    ) public initializer {
        rewardPool = IEqualizerRewardPool(_rewardPool);
        solidlyRouter = ISolidlyRouter(_solidlyRouter);

        lpToken0 = ISolidlyPair(_commonAddresses.want).token0();
        lpToken1 = ISolidlyPair(_commonAddresses.want).token1();

        __BaseStrategy_init(_commonAddresses, _rewards);
        _giveAllowances();
    }

    function balanceOfPool() public view override returns (uint) {
        return rewardPool.balanceOf(address(this));
    }

    function stratName() public pure override returns (string memory) {
        return "Equalizer";
    }

    function _deposit(uint _amount) internal override {
        rewardPool.deposit(_amount);
    }

    function _withdraw(uint _amount) internal override {
        if (_amount > 0) {
            rewardPool.withdraw(_amount);
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        rewardPool.getReward();
    }

    function _swapNativeToWant() internal override {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        uint256 lp0Amt = nativeBal / 2;
        uint256 lp1Amt = nativeBal - lp0Amt;
        bool stable = ISolidlyPair(want).stable();

        if (stable) {
            uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
            uint256 out0 = IBeefySwapper(swapper).getAmountOut(native, lpToken0, lp0Amt) * 1e18 / lp0Decimals;
            uint256 out1 = IBeefySwapper(swapper).getAmountOut(native, lpToken1, lp1Amt) * 1e18 / lp1Decimals;
            (uint256 amountA, uint256 amountB,) = ISolidlyRouter(solidlyRouter).quoteAddLiquidity(lpToken0, lpToken1, stable, out0, out1);
            amountA = amountA * 1e18 / lp0Decimals;
            amountB = amountB * 1e18 / lp1Decimals;
            uint256 ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = nativeBal * 1e18 / (ratio + 1e18);
            lp1Amt = nativeBal - lp0Amt;
        }

        if (lpToken0 != native) {
            IBeefySwapper(swapper).swap(native, lpToken0, lp0Amt);
        }

        if (lpToken1 != native) {
            IBeefySwapper(swapper).swap(native, lpToken1, lp1Amt);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        ISolidlyRouter(solidlyRouter).addLiquidity(lpToken0, lpToken1, stable, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
    }

    function _giveAllowances() internal {
        uint max = type(uint).max;
        _approve(want, address(rewardPool), max);
        _approve(native, address(swapper), max);

        _approve(lpToken0, address(solidlyRouter), 0);
        _approve(lpToken0, address(solidlyRouter), max);

        _approve(lpToken1, address(solidlyRouter), 0);
        _approve(lpToken1, address(solidlyRouter), max);
    }

    function _removeAllowances() internal {
        _approve(want, address(rewardPool), 0);
        _approve(native, address(swapper), 0);
        _approve(lpToken0, address(solidlyRouter), 0);
        _approve(lpToken0, address(solidlyRouter), 0);
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
