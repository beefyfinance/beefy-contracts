// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategyFactory {
    function native() external view returns (address);
    function keeper() external view returns (address);
    function beefyFeeRecipient() external view returns (address);
    function beefyFeeConfig() external view returns (address);
    function globalPause() external view returns (bool);
    function strategyPause(string calldata stratName) external view returns (bool);
}
