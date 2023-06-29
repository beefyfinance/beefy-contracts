// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IVelodromeGauge {
    function deposit(uint256 amount, address recipient) external;
    function withdraw(uint256 amount) external;
    function getReward(address account) external;
    function earned(address user) external view returns (uint256);
    function balanceOf(address user) external view returns (uint256);
}
