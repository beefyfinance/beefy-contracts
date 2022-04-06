// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGauge {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function withdrawAll() external;
    function balanceOf(address _account) external view returns (uint256);
    function earned(address _account) external view returns (uint256);
    function getReward() external;
    function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external;
    function TOKEN() external view returns (address);
}
