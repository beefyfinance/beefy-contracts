// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-5/contracts/utils/math/Math.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";
import "./IMellow.sol";

contract StrategyAeroAutopilot is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    address public lpToken0;
    address public lpToken1;

    function initialize(
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
        lpToken0 = IMellowLpWrapper(want).token0();
        lpToken1 = IMellowLpWrapper(want).token1();
    }

    function stratName() public pure override returns (string memory) {
        return "AeroAutopilot";
    }

    function balanceOfPool() public pure override returns (uint) {
        return 0;
    }

    function _deposit(uint amount) internal override {}

    function _withdraw(uint amount) internal override {}

    function _emergencyWithdraw() internal override {}

    function _claim() internal override {
        IMellowLpWrapper(want).getRewards(address(this));
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        address output = depositToken == address(0) ? native : depositToken;
        if (output != native) {
            _swap(native, output);
        }

        (address router,) = ISimplifiedSwapInfo(swapper).swapInfo(output, want);
        if (router != address(0)) {
            _swap(output, want);
            return;
        }

        IMellowLpWrapper lp = IMellowLpWrapper(want);
        (uint toLp0, uint toLp1) = _splitOutputPerBalance(output, lp);
        _swap(output, lpToken0, toLp0);
        _swap(output, lpToken1, toLp1);

        uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        uint lpAmount = _getLpAmountToMint(lp, lp0Bal, lp1Bal);

        IERC20(lpToken0).forceApprove(want, lp0Bal);
        IERC20(lpToken1).forceApprove(want, lp1Bal);
        lp.mint(IMellowLpWrapper.MintParams(lpAmount, lp0Bal, lp1Bal, address(this), block.timestamp));
    }

    function _splitOutputPerBalance(address output, IMellowLpWrapper lp) internal view returns (uint, uint) {
        uint totalSupply = lp.totalSupply();
        (uint amount0, uint amount1) = lp.previewMint(totalSupply);
        (uint160 sqrtPriceX96,,,,,) = ICLPool(lp.pool()).slot0();
        uint price = (uint(sqrtPriceX96) * 1e18 / (2 ** 96)) ** 2;
        uint amount0inLp1 = amount0 * price / 1e36;
        uint outputBal = IERC20(output).balanceOf(address(this));
        uint toLp0 = outputBal * amount0inLp1 / (amount0inLp1 + amount1);
        uint toLp1 = outputBal - toLp0;
        return (toLp0, toLp1);
    }

    function _getLpAmountToMint(IMellowLpWrapper lp, uint lp0Bal, uint lp1Bal) internal view returns (uint) {
        uint totalSupply = lp.totalSupply();
        (uint total0, uint total1) = lp.previewMint(totalSupply);
        uint lpAmount = Math.min(
            (lp0Bal == 0 || total0 == 0) ? type(uint).max : totalSupply * lp0Bal / total0,
            (lp1Bal == 0 || total1 == 0) ? type(uint).max : totalSupply * lp1Bal / total1
        );

        (uint actual0, uint actual1) = lp.previewMint(lpAmount);
        if (lp0Bal < actual0 || lp1Bal < actual1) {
            lpAmount--;
            // TODO
            // lpAmount = lpAmount / 10 * 10;
        }
        return lpAmount;
    }
}