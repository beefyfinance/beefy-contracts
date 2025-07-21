// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/stargate/IStargateRouter.sol";
import "../../interfaces/stargate/IStargateRouterETH.sol";
import "../../interfaces/common/ISolidlyRouter.sol";

import "./StrategyStargateInitializable.sol";

contract StrategyStargateSolidly is StrategyStargateInitializable {
    using SafeERC20 for IERC20;

    ISolidlyRouter.Routes[] public outputToNativeRoute;
    ISolidlyRouter.Routes[] public outputToDepositRoute;

    function initialize(
        address _want,
        uint256 _poolId,
        address _chef,
        address _stargateRouter,
        uint256 _routerPoolId,
        CommonAddresses calldata _commonAddresses,
        ISolidlyRouter.Routes[] memory _outputToNativeRoute,
        ISolidlyRouter.Routes[] memory _outputToDepositRoute
    ) public initializer {
        __StrategyStargate_init(
            _want,
            _poolId,
            _chef,
            _stargateRouter,
            _routerPoolId,
            _commonAddresses
        );

        output = _outputToNativeRoute[0].from;
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1].to;
        depositToken = _outputToDepositRoute[_outputToDepositRoute.length - 1].to;

        for (uint256 i; i < _outputToNativeRoute.length;) {
            outputToNativeRoute.push(_outputToNativeRoute[i]);
            unchecked { ++i; }
        }

        for (uint256 i; i < _outputToDepositRoute.length;) {
            outputToDepositRoute.push(_outputToDepositRoute[i]);
            unchecked { ++i; }
        }

        _giveAllowances();
    }

    function _swapToNative(uint256 _amountIn) internal override {
        ISolidlyRouter(unirouter).swapExactTokensForTokens(
            _amountIn, 0, outputToNativeRoute, address(this), block.timestamp
        );
    }

    function _addLiquidity() internal override {
        uint256 toDeposit = IERC20(output).balanceOf(address(this));
        ISolidlyRouter(unirouter).swapExactTokensForTokens(
            toDeposit, 0, outputToDepositRoute, address(this), block.timestamp
        );
        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));
        IStargateRouter(stargateRouter).addLiquidity(routerPoolId, depositBal, address(this));
    }

    function _getAmountOut(uint256 _amountIn) internal view override returns (uint256) {
        (uint256 nativeOut,) = ISolidlyRouter(unirouter).getAmountOut(_amountIn, output, native);
        return nativeOut;
    }

    function _solidlyToRoute(ISolidlyRouter.Routes[] memory _route) internal pure returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint256 i; i < _route.length;) {
            route[i + 1] = _route[i].to;
            unchecked { ++i; }
        }
        return route;
    }

    function outputToNative() external view returns (address[] memory) {
        return _solidlyToRoute(outputToNativeRoute);
    }

    function outputToDeposit() external view returns (address[] memory) {
        return _solidlyToRoute(outputToDepositRoute);
    }
}