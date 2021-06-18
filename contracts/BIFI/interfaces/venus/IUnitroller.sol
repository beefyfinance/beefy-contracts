// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IUnitroller {
    function claimVenus(address holder) external;
    function enterMarkets(address[] memory _vtokens) external;
    function exitMarket(address _vtoken) external;
    function getAssetsIn(address account) view external returns (address[] memory);
    function getAccountLiquidity(address account) view external returns (uint, uint, uint);
}