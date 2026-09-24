// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVenusComptroller {
    function getRewardDistributors() external view returns (address[] memory);
    function enterMarkets(address[] memory _iTokens) external;
}