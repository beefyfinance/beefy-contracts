// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IBentoPool {
    function getAmountOut(bytes calldata data) external view returns (uint256 finalAmountOut);
}