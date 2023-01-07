// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/UniswapV3Utils.sol";
import "./StrategyMVX.sol";

contract StrategyMVXUniV3 is StrategyMVX {

    // Route
    bytes public nativeToWantPath;

    function initialize(
        address _chef,
        address[] calldata _nativeToWantRoute,
        uint24[] calldata _nativeToWantFees,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StrategyMVX_init(_chef, _commonAddresses);
        native = _nativeToWantRoute[0];
        want = _nativeToWantRoute[_nativeToWantRoute.length - 1];

        nativeToWantPath = UniswapV3Utils.routeToPath(_nativeToWantRoute, _nativeToWantFees);

        _giveAllowances();
    }

    function swapRewards() internal override {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        UniswapV3Utils.swap(unirouter, nativeToWantPath, nativeBal);
    }

    function nativeToWant() external view override returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToWantPath);
    }
}
