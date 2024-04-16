// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeERC20Upgradeable, IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/IVelodromeGauge.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../../interfaces/velodrome-v2/IPoolFactory.sol";
import "../../interfaces/velodrome-v2/IVoter.sol";
import "../Common/BaseStrategy.sol";

contract StrategyVelodrome is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error TokenNotValidReward(address token);

    address public gauge;
    address public factory;
    bool public stable;
    address public lpToken0;
    address public lpToken1;

    function initialize(
        BaseStrategyAddresses calldata _baseStrategyAddresses,
        CommonAddresses calldata _commonAddresses
    ) external initializer  {
        __BaseStrategy_init(_baseStrategyAddresses, _commonAddresses);
        factory = ISolidlyPair(want).factory();
        address voter = IPoolFactory(factory).voter();
        gauge = IVoter(voter).gauges(want);
        stable = ISolidlyPair(want).stable();

        (lpToken0, lpToken1) = (ISolidlyPair(want).token0(), ISolidlyPair(want).token1());

        depositTokens.push(lpToken0);
        depositTokens.push(lpToken1);
    }

    function balanceOfPool() public view override returns (uint256) {
        return IVelodromeGauge(gauge).balanceOf(address(this));
    }

    function rewardsAvailable() public view override returns (uint256) {
        return IVelodromeGauge(gauge).earned(address(this));
    }

    function callReward() public view override returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 rewardBal = rewardsAvailable();
        uint256 nativeOut;
        if (rewardBal > 0) {
            nativeOut = _getAmountOut(rewards[0], native, rewardBal);
        }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function _deposit(uint256 _amount) internal override {
        IERC20Upgradeable(want).forceApprove(gauge, _amount);
        IVelodromeGauge(gauge).deposit(_amount, address(this));
    }

    function _withdraw(uint256 _amount) internal override {
        IVelodromeGauge(gauge).withdraw(_amount);
    }

    function _emergencyWithdraw() internal override {
        IVelodromeGauge(gauge).withdraw(balanceOfPool());
    }

    function _claim() internal override {
        IVelodromeGauge(gauge).getReward(address(this));
    }

    function _getDepositAmounts() internal view override returns (uint256[] memory depositAmounts) {
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));
        uint256 lp0Amt = nativeBal / 2;
        uint256 lp1Amt = nativeBal - lp0Amt;

        if (stable) {
            uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
            uint256 out0 = lpToken0 != native ? _getAmountOut(native, lpToken0, lp0Amt) * 1e18 / lp0Decimals : lp0Amt;
            uint256 out1 = lpToken1 != native ? _getAmountOut(native, lpToken1, lp1Amt) * 1e18 / lp1Decimals  : lp1Amt;
            (uint256 amountA, uint256 amountB,) = ISolidlyRouter(unirouter).quoteAddLiquidity(
                lpToken0, lpToken1, stable, factory, out0, out1
            );
            amountA = amountA * 1e18 / lp0Decimals;
            amountB = amountB * 1e18 / lp1Decimals;
            uint256 ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = nativeBal * 1e18 / (ratio + 1e18);
            lp1Amt = nativeBal - lp0Amt;
        }

        (depositAmounts[0], depositAmounts[1]) = (lp0Amt, lp1Amt);
    }

    function _addLiquidity() internal override {
        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));
        IERC20Upgradeable(lpToken0).forceApprove(unirouter, lp0Bal);
        IERC20Upgradeable(lpToken1).forceApprove(unirouter, lp1Bal);
        ISolidlyRouter(unirouter).addLiquidity(
            lpToken0,
            lpToken1,
            stable,
            lp0Bal,
            lp1Bal,
            1,
            1,
            address(this),
            block.timestamp
        );
    }

    function _verifyRewardToken(address _token) internal view override {
        if (_token == want) revert TokenNotValidReward(_token);
    }
}
