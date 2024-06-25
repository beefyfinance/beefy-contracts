// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/UniswapV3Utils.sol";
import "../../interfaces/camelot/ICamelotRouter.sol";
import "./StrategyHop.sol";

contract StrategyHopCamelotUniV3 is StrategyHop {
    using SafeERC20 for IERC20;
    
    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToDepositRoute;
    bytes public nativeToDepositPath;
    address public uniswapRouter;

    function initialize(
        address _want,
        address _rewardPool,
        address _stableRouter,
        address[] calldata _outputToNativeRoute,
        address[] calldata _nativeToDepositRoute,
        uint24[] calldata _nativeToDepositFees,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StrategyHop_init(_want, _rewardPool, _stableRouter, _commonAddresses);

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        depositToken = _nativeToDepositRoute[_nativeToDepositRoute.length - 1];
        depositIndex = IStableRouter(stableRouter).getTokenIndex(depositToken);

        outputToNativeRoute = _outputToNativeRoute;
        nativeToDepositPath = UniswapV3Utils.routeToPath(_nativeToDepositRoute, _nativeToDepositFees);
        uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

        _giveAllowances();
    }

    function _swapToNative(uint256 totalFee) internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this)) * totalFee / DIVISOR;
        ICamelotRouter(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(toNative, 0, outputToNativeRoute, address(this), address(0), block.timestamp);
    }

    function _swapToDeposit() internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this));
        ICamelotRouter(unirouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(toNative, 0, outputToNativeRoute, address(this), address(0), block.timestamp);
        uint256 toDeposit = IERC20(native).balanceOf(address(this));
        UniswapV3Utils.swap(uniswapRouter, nativeToDepositPath, toDeposit);
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

    function nativeToDeposit() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToDepositPath);
    }

    function _giveAllowances() internal override {
        IERC20(want).safeApprove(rewardPool, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(uniswapRouter, type(uint).max);
        IERC20(depositToken).safeApprove(stableRouter, type(uint).max);
    }

    function _removeAllowances() internal override {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(uniswapRouter, 0);
        IERC20(depositToken).safeApprove(stableRouter, 0);
    }
}
