// SPDX-License-Identifier: MIT

pragma solidity >0.6.0;
pragma experimental ABIEncoderV2;

interface IJarvisMinter {
    struct MintParams {
        uint256 minNumTokens;
        uint256 collateralAmount;
        uint256 expiration;
        address recipient;
    }
    struct RedeemParams {
    uint256 numTokens;
    uint256 minCollateral;
    uint256 expiration;
    address recipient;
  }
    function mint(
        MintParams memory mintParams
    ) external returns (uint256 syntheticTokensMinted, uint256 feePaid);

    function redeem(
        RedeemParams calldata redeemParams
    ) external returns (uint256 collateralRedeemed, uint256 feePaid);

    function getMintTradeInfo(
        uint256 _collateralAmount
    ) external view returns (uint256 synthTokensReceived, uint256 feePaid);

    function getRedeemTradeInfo(
        uint256 _syntTokensAmount
    ) external view returns (uint256 collateralAmountReceived, uint256 feePaid);
}