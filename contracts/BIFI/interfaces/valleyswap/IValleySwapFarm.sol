// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IValleySwapFarm {
    function pendingVS(uint _pid, address _user) external view returns (uint);
    function deposit(uint _pid, uint _amount) external;
    function withdraw(uint _pid, uint _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint _pid) external;
}
