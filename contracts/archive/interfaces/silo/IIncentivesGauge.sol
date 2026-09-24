// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIncentivesGauge {
    function claimRewards(address to) external;
}