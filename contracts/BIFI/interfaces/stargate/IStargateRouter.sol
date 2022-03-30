// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IStargateRouter {
        function addLiquidity(
        uint256 _poolId,
        uint256 _amountLD,
        address _to
    ) external;
}