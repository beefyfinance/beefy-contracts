// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IChainlinkMorpho {
    function BASE_VAULT() external view returns (address);
    function price() external view returns (uint256);
}