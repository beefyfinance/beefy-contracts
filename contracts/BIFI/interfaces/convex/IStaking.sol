// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

interface IStaking {
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function getReward(address _account) external;
}