// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IAuraRewardPool {
    function deposit(uint256 amount) external;
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function earned(address account) external view returns (uint256);
    function getReward() external;
    function balanceOf(address account) external view returns (uint256);
    function stakingToken() external view returns (address);
    function rewardsToken() external view returns (address);
    function withdrawAndUnwrap(uint256 _amount, bool claim) external;
}
