// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IYuzuMasterChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function emergencyWithdraw(uint256 _pid) external;
    function pendingTokens(uint256 _pid, address _user) external view returns (address[] calldata tokens, uint256[] calldata amounts);
    function pendingYuzu(uint256 _pid, address _user) external view returns (uint256);
}