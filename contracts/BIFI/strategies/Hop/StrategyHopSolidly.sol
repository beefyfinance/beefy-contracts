// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/common/ISolidlyRouter.sol";
import "./StrategyHop.sol";

contract StrategyHopSolidly is StrategyHop {
    // Routes
    ISolidlyRouter.Route[] public outputToNativeRoute;
    ISolidlyRouter.Route[] public outputToDepositRoute;

    function initialize(
        address _want,
        address _rewardPool,
        address _stableRouter,
        ISolidlyRouter.Route[] calldata _outputToNativeRoute,
        ISolidlyRouter.Route[] calldata _outputToDepositRoute,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StrategyHop_init(_want, _rewardPool, _stableRouter, _commonAddresses);
        for (uint i; i < _outputToNativeRoute.length; ++i) {
            outputToNativeRoute.push(_outputToNativeRoute[i]);
        }

        for (uint i; i < _outputToDepositRoute.length; ++i) {
            outputToDepositRoute.push(_outputToDepositRoute[i]);
        }

        output = outputToNativeRoute[0].from;
        native = outputToNativeRoute[outputToNativeRoute.length - 1].to;
        depositToken = _outputToDepositRoute[_outputToDepositRoute.length - 1].to;
        depositIndex = IStableRouter(stableRouter).getTokenIndex(depositToken);

        _giveAllowances();
    }

    function _swapToNative(uint256 totalFee) internal virtual override {
        uint256 toNative = IERC20(output).balanceOf(address(this)) * totalFee / DIVISOR;
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);
    }

    function _swapToDeposit() internal virtual override {
        uint256 toDeposit = IERC20(output).balanceOf(address(this));
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toDeposit, 0, outputToDepositRoute, address(this), block.timestamp);
    }

    function _getAmountOut(uint256 inputAmount) internal view virtual override returns (uint256) {
        (uint256 nativeOut,) = ISolidlyRouter(unirouter).getAmountOut(inputAmount, output, native);
        return nativeOut;
    }

    function outputToNative() external view virtual override returns (address[] memory) {
        ISolidlyRouter.Route[] memory _route = outputToNativeRoute;
        return _solidlyToRoute(_route);
    }

    function outputToDeposit() external view virtual override returns (address[] memory) {
        ISolidlyRouter.Route[] memory _route = outputToDepositRoute;
        return _solidlyToRoute(_route);
    }

    function _solidlyToRoute(ISolidlyRouter.Route[] memory _route) internal pure virtual returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint i; i < _route.length; ++i) {
            route[i + 1] = _route[i].to;
        }
        return route;
    }
}
