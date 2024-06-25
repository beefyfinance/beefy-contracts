// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/common/ISolidlyRouter.sol";
import "../../utils/UniswapV3Utils.sol";
import "./StrategyHop.sol";

contract StrategyHopSolidlyUniV3 is StrategyHop {
    using SafeERC20 for IERC20;
    // Routes
    ISolidlyRouter.Routes[] public outputToNativeRoute;
    bytes public nativeToWantPath;

    address public unirouterV3;

    function initialize(
        address _want,
        address _rewardPool,
        address _stableRouter,
        ISolidlyRouter.Routes[] calldata _outputToNativeRoute,
        address _unirouterV3,
        address[] calldata _nativeToWantRoute,
        uint24[] calldata _nativeToWantFees,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StrategyHop_init(_want, _rewardPool, _stableRouter, _commonAddresses);
        for (uint i; i < _outputToNativeRoute.length; ++i) {
            outputToNativeRoute.push(_outputToNativeRoute[i]);
        }

        output = outputToNativeRoute[0].from;
        native = outputToNativeRoute[outputToNativeRoute.length - 1].to;
        depositIndex = IStableRouter(stableRouter).getTokenIndex(want);

        nativeToWantPath = UniswapV3Utils.routeToPath(_nativeToWantRoute, _nativeToWantFees);
        unirouterV3 = _unirouterV3;

        _giveAllowances();
    }

    function _swapToNative(uint256 totalFee) internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this)) * totalFee / DIVISOR;
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);
    }

    function _swapToWant() internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this));
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);
        uint256 toWant = IERC20(native).balanceOf(address(this));
        UniswapV3Utils.swap(unirouterV3, nativeToWantPath, toWant);
    }

    function _getAmountOut(uint256 inputAmount) internal view virtual override returns (uint256) {
        (uint256 nativeOut,) = ISolidlyRouter(unirouter).getAmountOut(inputAmount, output, native);
        return nativeOut;
    }

    function outputToNative() external view virtual override returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = outputToNativeRoute;
        return _solidlyToRoute(_route);
    }

    function outputToWant() external view virtual override returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToWantPath);
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
        IERC20(want).safeApprove(stableRouter, type(uint).max);
        IERC20(lpToken).safeApprove(stableRouter, type(uint).max);
        IERC20(lpToken).safeApprove(rewardPool, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouterV3, type(uint).max);
    }

    function _removeAllowances() internal virtual override {
        IERC20(want).safeApprove(stableRouter, 0);
        IERC20(lpToken).safeApprove(stableRouter, 0);
        IERC20(lpToken).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouterV3, 0);
    }
}
