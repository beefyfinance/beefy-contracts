// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICometRewards {
    function claim(address comet, address source, bool shouldAccrue) external;
    function rewardConfig(address comet) external view 
        returns (address token, uint64 rescaleFactor, bool shouldUpscale, uint256 multiplier);
}
