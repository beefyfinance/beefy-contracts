// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/stargate/IStargateRouter.sol";
import "../../interfaces/stargate/IStargateRouterETH.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../utils/BalancerUtils.sol";

import "./StrategyStargateInitializable.sol";

contract StrategyStargateBal is StrategyStargateInitializable {
    using SafeERC20 for IERC20;
    using BalancerUtils for IBalancerVault;

    BalancerUtils.BatchSwapInfo public outputToNativePath;
    BalancerUtils.BatchSwapInfo public outputToDepositPath;

    function initialize(
        address _want,
        uint256 _poolId,
        address _chef,
        address _stargateRouter,
        uint256 _routerPoolId,
        CommonAddresses calldata _commonAddresses,
        bytes32[] memory _outputToNativePools,
        bytes32[] memory _outputToDepositPools,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToDepositRoute
    ) public initializer {
        __StrategyStargate_init(
            _want,
            _poolId,
            _chef,
            _stargateRouter,
            _routerPoolId,
            _commonAddresses
        );
        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];

        depositToken = _outputToDepositRoute[_outputToDepositRoute.length - 1];

        BalancerUtils.assignBatchSwapInfo(outputToNativePath, _outputToNativePools, _outputToNativeRoute);
        BalancerUtils.assignBatchSwapInfo(outputToDepositPath, _outputToDepositPools, _outputToDepositRoute);

        _giveAllowances();
    }

    function _swapToNative(uint256 _amountIn) internal override {
        IBalancerVault(unirouter).swap(outputToNativePath, _amountIn);
    }

    function _addLiquidity() internal override {
        if (depositToken != native) {
            IBalancerVault(unirouter).swap(
                outputToDepositPath, IERC20(output).balanceOf(address(this))
            );
            uint256 depositBal = IERC20(depositToken).balanceOf(address(this));
            IStargateRouter(stargateRouter).addLiquidity(routerPoolId, depositBal, address(this));
        } else {
            IWrappedNative(native).withdraw(IERC20(native).balanceOf(address(this)));
            uint256 toDeposit = address(this).balance;
            IStargateRouterETH(stargateRouter).addLiquidityETH{value: toDeposit}();
        }
    }

    function _getAmountOut(uint256 _amountIn) internal view override returns (uint256) {
        uint256[] memory amountsOut = IBalancerVault(unirouter).getAmountsOut(
                outputToNativePath, _amountIn
            );
        return amountsOut[amountsOut.length - 1];
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativePath.route;
    }

    function outputToDeposit() external view returns (address[] memory) {
        return outputToDepositPath.route;
    }

    receive() external payable {}
}
