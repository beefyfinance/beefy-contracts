// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/common/ISolidlyRouter.sol";
import "./StrategyHop.sol";

contract StrategyHopSolidly is StrategyHop {
    // Routes
    ISolidlyRouter.Routes[] public outputToNativeRoute;
    ISolidlyRouter.Routes[] public outputToWantRoute;

    function initialize(
        address _want,
        address _rewardPool,
        address _stableRouter,
        ISolidlyRouter.Routes[] calldata _outputToNativeRoute,
        ISolidlyRouter.Routes[] calldata _outputToWantRoute,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StrategyHop_init(_want, _rewardPool, _stableRouter, _commonAddresses);
        for (uint i; i < _outputToNativeRoute.length; ++i) {
            outputToNativeRoute.push(_outputToNativeRoute[i]);
        }

        for (uint i; i < _outputToWantRoute.length; ++i) {
            outputToWantRoute.push(_outputToWantRoute[i]);
        }

        output = outputToNativeRoute[0].from;
        native = outputToNativeRoute[outputToNativeRoute.length - 1].to;
        depositIndex = IStableRouter(stableRouter).getTokenIndex(want);

        _giveAllowances();
    }

    function _swapToNative(uint256 totalFee) internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this)) * totalFee / DIVISOR;
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);
    }

    function _swapToWant() internal virtual override {
        uint256 toWant = IERC20(output).balanceOf(address(this));
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toWant, 0, outputToWantRoute, address(this), block.timestamp);
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
        ISolidlyRouter.Routes[] memory _route = outputToWantRoute;
        return _solidlyToRoute(_route);
    }

    function _solidlyToRoute(ISolidlyRouter.Routes[] memory _route) internal pure virtual returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint i; i < _route.length; ++i) {
            route[i + 1] = _route[i].to;
        }
        return route;
    }
}
