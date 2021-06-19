// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IComptroller {
    function claimComp(address holder, address[] calldata _iTokens) external;
    function enterMarkets(address[] memory _iTokens) external;
}