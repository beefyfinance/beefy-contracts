// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './AlgebraPath.sol';
import "../interfaces/common/IUniswapRouterV3WithDeadline.sol";

library AlgebraUtils {
    using Path for bytes;

    // Swap along an encoded path using known amountIn
    function swap(
        address _router,
        bytes memory _path,
        uint256 _amountIn
    ) internal returns (uint256 amountOut) {
        IUniswapRouterV3WithDeadline.ExactInputParams memory params = IUniswapRouterV3WithDeadline.ExactInputParams({
            path: _path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: 0
        });
        return IUniswapRouterV3WithDeadline(_router).exactInput(params);
    }

    // Convert encoded path to token route
    function pathToRoute(bytes memory _path) internal pure returns (address[] memory) {
        uint256 numPools = _path.numPools();
        address[] memory route = new address[](numPools + 1);
        for (uint256 i; i < numPools; i++) {
            (address tokenA, address tokenB) = _path.decodeFirstPool();
            route[i] = tokenA;
            route[i + 1] = tokenB;
            _path = _path.skipToken();
        }
        return route;
    }

    // Convert token route to encoded path
    // uint24 type for fees so path is packed tightly
    function routeToPath(address[] memory _route) internal pure returns (bytes memory path) {
        path = abi.encodePacked(_route[0]);
        for (uint256 i = 1; i < _route.length; i++) {
            path = abi.encodePacked(path, _route[i]);
        }
    }
}
