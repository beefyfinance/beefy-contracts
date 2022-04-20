// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICakePool {
    function deposit(uint256 _amount, uint256 _lockDuration) external;
    function withdrawByAmount(uint256 _amount) external;
    function unlock(address _user) external;

    function userInfo(address _user)
        external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, bool, uint256);
}