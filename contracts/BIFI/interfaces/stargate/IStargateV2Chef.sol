// SPDX-License-Identifier: MIT

pragma solidity >0.6.0;

interface IStargateV2Chef {
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 _amount) external;
    function emergencyWithdraw(address token) external;
    function balanceOf(address token, address user) external view returns (uint256);
    function claim(address[] calldata lpTokens) external;
}