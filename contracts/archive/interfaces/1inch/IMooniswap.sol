// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IMooniswap {
    function fee() external view returns (uint256);

    function tokens(uint256 i) external view returns (address);

    function deposit(uint256[2] memory maxAmounts, uint256[2] memory minAmounts) external payable returns(uint256 fairSupply, uint256[2] memory receivedAmounts);

    function withdraw(uint256 amount, uint256[] calldata minReturns) external;

    function getBalanceForAddition(address token) external view returns (uint256);

    function getBalanceForRemoval(address token) external view returns (uint256);

    function getReturn(
        address fromToken,
        address destToken,
        uint256 amount
    )
    external
    view
    returns (uint256 returnAmount);

    function swap(
        address fromToken,
        address destToken,
        uint256 amount,
        uint256 minReturn,
        address referral
    )
    external
    payable
    returns (uint256 returnAmount);
}
