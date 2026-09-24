// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IStargateV2Router {
    function token() external view returns (address);
    function lpToken() external view returns (address);
    function deposit(address receiver, uint256 amount) external payable returns (uint256);
    function redeem(uint256 amount, address receiver) external returns (uint256);
    function sharedDecimals() external view returns (uint8);
}