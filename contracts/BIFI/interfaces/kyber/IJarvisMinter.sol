// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

interface IJarvisMinter {
    struct MintParams {
        address derivative;
        uint256 minNumTokens;
        uint256 collateralAmount;
        uint256 feePercentage;
        uint256 expiration;
        address recipient;
    }
    function mint(MintParams memory mintParams) external returns (uint256 syntheticTokensMinted, uint256 feePaid);
}