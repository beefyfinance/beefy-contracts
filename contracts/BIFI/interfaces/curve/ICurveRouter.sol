// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

interface ICurveRouter {

    function exchange_multiple(
        address[9] calldata _route,
        uint[3][4] calldata _swap_params,
        uint _amount,
        uint _expected
    ) external returns (uint);
}