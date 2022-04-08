// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface ISolarStableRouter {
    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256);

    function getNumberOfTokens() external view returns (uint256);
    function getTokenIndex(address tokenAddress) external view returns (uint8);
}