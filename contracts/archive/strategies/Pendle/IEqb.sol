// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IEqbBooster {
    function poolInfo(uint256 _pid) external view returns (address market, address token, address rewardPool);
    function deposit(uint256 pid, uint256 amount, bool stake) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function withdrawAll(uint256 _pid) external;
    function xEqb() external view returns (address);
    function eqb() external view returns (address);
    function earmarkRewards(uint256 _pid) external;
}

interface IXEqb {
    function balanceOf(address user) external view returns(uint256);
    function getUserRedeemsLength(address userAddress) external view returns (uint256);
    function getUserRedeem(address userAddress, uint256 redeemIndex) external view returns (uint256 eqbAmount, uint256 xEqbAmount, uint256 endTime);
    function minRedeemDuration() external view returns (uint);
    function redeem(uint256 xEqbAmount,uint256 duration) external;
    function finalizeRedeem(uint256 redeemIndex) external;
}