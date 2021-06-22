// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IAutoFarmV2 {
    function poolInfo(uint256 _pid) external view returns (address, uint256, uint256, uint256, address);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function pendingAUTO(uint256 _pid, address _user) external view returns (uint256);
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256);
    function deposit(uint256 _pid, uint256 _wantAmt) external;
    function withdraw(uint256 _pid, uint256 _wantAmt) external;
    function withdrawAll(uint256 _pid) external;
    function emergencyWithdraw(uint256 _pid) external;
}