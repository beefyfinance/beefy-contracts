// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IYuzuSwapMining {
    function withdrawAll() external;
    function pendingYuzuAll(address _user) external view returns (uint256);
}