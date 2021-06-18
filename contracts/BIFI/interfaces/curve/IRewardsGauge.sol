// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IRewardsGauge {
    function balanceOf(address account) external view returns (uint256);
    function claim_rewards(address _addr) external;
    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;
}