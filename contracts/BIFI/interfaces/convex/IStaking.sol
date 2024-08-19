// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

interface IStaking {
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 _amount) external;
    function stakeFor(address _to, uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function withdraw(uint256 _amount, bool _claim) external returns(bool);
    function emergencyWithdraw(uint256 _amount) external returns(bool);
    function getReward(address _account) external;
}