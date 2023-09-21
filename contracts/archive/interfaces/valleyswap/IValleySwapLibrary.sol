// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IValleySwapLibrary {

    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) external view returns (uint256[] memory amounts);

}
