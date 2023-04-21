// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/camelot/ICamelotRouter.sol";
import "./StrategyHop.sol";

contract StrategyHopCamelot is StrategyHop {
    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToDepositRoute;

    function initialize(
        address _want,
        address _rewardPool,
        address _stableRouter,
        address[] calldata _outputToNativeRoute,
        address[] calldata _outputToDepositRoute,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StrategyHop_init(_want, _rewardPool, _stableRouter, _commonAddresses);

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        depositToken = _outputToDepositRoute[_outputToDepositRoute.length - 1];
        depositIndex = IStableRouter(stableRouter).getTokenIndex(depositToken);

        outputToNativeRoute = _outputToNativeRoute;
        outputToDepositRoute = _outputToDepositRoute;

        _giveAllowances();
    }

    function _swapToNative(uint256 totalFee) internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this)) * totalFee / DIVISOR;
        ICamelotRouter(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(toNative, 0, outputToNativeRoute, address(this), address(0), block.timestamp);
    }

    function _swapToDeposit() internal virtual override {
        uint256 toDeposit = IERC20(output).balanceOf(address(this));
        ICamelotRouter(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(toDeposit, 0, outputToDepositRoute, address(this), address(0), block.timestamp);
    }

    function _getAmountOut(uint256 inputAmount) internal view virtual override returns (uint256) {
        uint256[] memory amountsOut = ICamelotRouter(unirouter).getAmountsOut(inputAmount, outputToNativeRoute);
        return amountsOut[amountsOut.length - 1];
    }

    function outputToNative() external view virtual override returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToDeposit() external view virtual override returns (address[] memory) {
        return outputToDepositRoute;
    }
}
