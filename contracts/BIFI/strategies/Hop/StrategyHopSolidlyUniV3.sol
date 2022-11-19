// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/common/ISolidlyRouter.sol";
import "../../utils/UniswapV3Utils.sol";
import "./StrategyHop.sol";

contract StrategyHopSolidlyUniV3 is StrategyHop {
    using SafeERC20 for IERC20;
    // Routes
    ISolidlyRouter.Routes[] public outputToNativeRoute;
    bytes public nativeToDepositPath;

    address public unirouterV3;

    constructor(
        address _want,
        address _rewardPool,
        address _stableRouter,
        ISolidlyRouter.Routes[] memory _outputToNativeRoute,
        address _unirouterV3,
        address[] memory _nativeToDepositRoute,
        uint24[] memory _nativeToDepositFees,
        CommonAddresses memory _commonAddresses
    ) StrategyHop(_want, _rewardPool, _stableRouter, _commonAddresses) {
        for (uint i; i < _outputToNativeRoute.length; ++i) {
            outputToNativeRoute.push(_outputToNativeRoute[i]);
        }

        output = outputToNativeRoute[0].from;
        native = outputToNativeRoute[outputToNativeRoute.length - 1].to;
        depositToken = _nativeToDepositRoute[_nativeToDepositRoute.length - 1];
        depositIndex = IStableRouter(stableRouter).getTokenIndex(depositToken);

        nativeToDepositPath = UniswapV3Utils.routeToPath(_nativeToDepositRoute, _nativeToDepositFees);
        unirouterV3 = _unirouterV3;

        _giveAllowances();
    }

    function _swapToNative(uint256 totalFee) internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this)) * totalFee / DIVISOR;
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);
    }

    function _swapToDeposit() internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this));
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);
        uint256 toDeposit = IERC20(native).balanceOf(address(this));
        UniswapV3Utils.swap(unirouterV3, nativeToDepositPath, toDeposit);
    }

    function _getAmountOut(uint256 inputAmount) internal view virtual override returns (uint256) {
        (uint256 nativeOut,) = ISolidlyRouter(unirouter).getAmountOut(inputAmount, output, native);
        return nativeOut;
    }

    function outputToNative() external view virtual override returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = outputToNativeRoute;
        return _solidlyToRoute(_route);
    }

    function outputToDeposit() external view virtual override returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToDepositPath);
    }

    function _solidlyToRoute(ISolidlyRouter.Routes[] memory _route) internal pure virtual returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint i; i < _route.length; ++i) {
            route[i + 1] = _route[i].to;
        }
        return route;
    }

    function _giveAllowances() internal virtual override {
        IERC20(want).safeApprove(rewardPool, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouterV3, type(uint).max);
        IERC20(depositToken).safeApprove(stableRouter, type(uint).max);
    }

    function _removeAllowances() internal virtual override {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouterV3, 0);
        IERC20(depositToken).safeApprove(stableRouter, 0);
    }
}
