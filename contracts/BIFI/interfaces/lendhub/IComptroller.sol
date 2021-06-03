// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IComptroller {
    function claimComp(address holder) external;
    function enterMarkets(address[] memory _vtokens) external;
    function exitMarket(address _vtoken) external;
    function getAssetsIn(address account) view external returns (address[] memory);
    function getAccountLiquidity(address account) view external returns (uint, uint, uint);
}