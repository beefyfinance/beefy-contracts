// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStargatePool {
    function amountLPtoLD(uint256 _amount) external view returns (uint256);
    function totalLiquidity() external view returns (uint256);
    function convertRate() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function pendingStargate(uint256 _pid, address _user) external view returns (uint256);
}