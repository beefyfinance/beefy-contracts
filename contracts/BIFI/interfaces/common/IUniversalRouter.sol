// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs) external;
    function poolManager() external view returns(address);
}