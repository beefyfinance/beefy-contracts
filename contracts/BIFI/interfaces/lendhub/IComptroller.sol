// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IComptroller {
    function claimComp(address holder, address[] calldata _iTokens) external;
    function enterMarkets(address[] memory _iTokens) external;
}