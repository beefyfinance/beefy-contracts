// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ILiquidityMining {
    function userInfo(address _user) external view returns (uint256, uint256, uint256);
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function claim() external;
}