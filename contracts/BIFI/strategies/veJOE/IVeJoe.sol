// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVeJoe {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getPendingVeJoe(address _user) external view returns (uint256);
    function userInfos(address _user) external view returns (uint256, uint256, uint256, uint256);
    function speedUpThreshold() external view returns (uint256);
    function claim() external;
    function joe() external view returns (address);
    function veJoe() external view returns (address);
}