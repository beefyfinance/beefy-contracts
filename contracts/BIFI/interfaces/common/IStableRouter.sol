// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IStableRouter {
    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256);
    function getNumberOfTokens() external view returns (uint256);
    function getTokenIndex(address tokenAddress) external view returns (uint8);
    function getTokenBalances(uint8 tokenIndex) external view returns (uint256);
    function getVirtualPrice() external view returns (uint256);
    function removeLiquidityOneToken(
        uint256 tokenAmount,
        uint8 tokenIndex,
        uint256 minAmount,
        uint256 deadline
    ) external returns (uint256);
}