// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

struct CurveRoute {
    address[11] route;
    uint256[5][5] swapParams;
    uint minAmount;
}

interface ICurveRouterV1 {

    function exchange(
        address[11] calldata _route,
        uint[5][5] calldata _swap_params,
        uint _amount,
        uint _expected
    ) external returns(uint);
}