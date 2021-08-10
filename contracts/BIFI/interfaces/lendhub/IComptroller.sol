// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IComptroller {
    function claimComp(address holder, address[] calldata _iTokens) external;
    function claimComp(address holder) external;
    function enterMarkets(address[] memory _iTokens) external;
    function pendingComptrollerImplementation() view external returns (address implementation);
}