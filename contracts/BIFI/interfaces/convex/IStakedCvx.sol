// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IStakedCvx {
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 _amount) external;
    function withdraw(uint256 _amount, bool claim) external;
    function getReward(address _account, bool _claimExtras, bool _stake) external;
}