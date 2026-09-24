// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITokemakVault {
    function deposit(uint256 _assets, address _reciever) external;
    function withdraw(uint256 _assets, address _reciever, address _owner) external;
    function balanceOf(address _account) external view returns (uint256);
    function getReward() external; 
    function asset() external returns (address);
}
