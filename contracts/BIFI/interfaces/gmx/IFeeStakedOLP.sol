// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFeeStakedOLP {
    function stake(address depositToken, uint256 amount) external;
    function unstake(address depositToken, uint256 amount) external;
    function claim(address receiver) external;
}
