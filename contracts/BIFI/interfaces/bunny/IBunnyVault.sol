// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface IBunnyVault {
    function deposit(uint256 _amount) external;
    function getReward() external;
    function withdrawUnderlying(uint256 _amount) external;
    function withdrawAll() external;
    function balanceOf(address _account) external view returns(uint256);
}
