// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

interface IBunnyVault {
    function deposit(uint256 _amount) external;
    function getReward() external;
    function withdrawUnderlying(uint256 _amount) external;
    function withdrawAll() external;
    function balanceOf(address _account) external view returns(uint256);
}
