// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma abicoder v1;

interface IGrandFarm {
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256);
    function depositWant(uint256 _pid, uint256 _amount) external;
    function withdrawWant(uint256 _pid, uint256 wantBalance) external;
    function emergencyWithdraw(uint256 _pid) external;
}