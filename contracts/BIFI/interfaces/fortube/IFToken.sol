// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFToken {
    function balanceOf(address account) external view returns (uint256);

    function calcBalanceOfUnderlying(address owner)
        external
        view
        returns (uint256);
}