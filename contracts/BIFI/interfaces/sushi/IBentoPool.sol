// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBentoPool {
    struct TokenAmount {
        address token;
        uint256 amount;
    }
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getAmountOut(bytes calldata data) external view returns (uint256 finalAmountOut);
    function getNativeReserves() external view returns (
        uint256 _nativeReserve0,
        uint256 _nativeReserve1,
        uint32 _blockTimestampLast
    );
    function burn(
        bytes calldata data
    ) external returns (TokenAmount[] memory withdrawnAmounts);
}