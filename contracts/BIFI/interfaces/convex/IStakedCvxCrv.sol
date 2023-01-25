// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

interface IStakedCvxCrv {
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 _amount, address _to) external;
    function withdraw(uint256 _amount) external;
    function getReward(address _account) external;
    function setRewardWeight(uint256 _weight) external;
    function userRewardWeight(address _account) external view returns (uint256);
}