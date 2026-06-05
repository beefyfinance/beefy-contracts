// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './Path.sol';
import "../interfaces/common/IUniversalRouter.sol";

library UniversalRouter {
    using Path for bytes;

    function swap(
        address _router,
        bytes memory _path,
        uint256 _amountIn
    ) internal {
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(1), _amountIn, uint256(0), _path, true);
        IUniversalRouter(_router).execute(abi.encodePacked(bytes1(uint8(0x00))), inputs);
    }

    function pathToRoute(bytes memory _path) internal pure returns (address[] memory) {
        uint256 numPools = _path.numPools();
        address[] memory route = new address[](numPools + 1);
        for (uint256 i; i < numPools; i++) {
            (address tokenA, address tokenB,) = _path.decodeFirstPool();
            route[i] = tokenA;
            route[i + 1] = tokenB;
            _path = _path.skipToken();
        }
        return route;
    }

    function routeToPath(
        address[] memory _route,
        uint24[] memory _fee
    ) internal pure returns (bytes memory path) {
        path = abi.encodePacked(_route[0]);
        uint256 feeLength = _fee.length;
        for (uint256 i = 0; i < feeLength; i++) {
            path = abi.encodePacked(path, _fee[i], _route[i+1]);
        }
    }
}
