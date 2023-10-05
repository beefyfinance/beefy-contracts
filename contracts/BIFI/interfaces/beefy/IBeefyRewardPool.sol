// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IBeefyRewardPool {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function earned(address user, address reward) external view returns (uint256);
    function notifyRewardAmount(address reward, uint256 amount, uint256 duration) external;
    function removeReward(address reward, address recipient) external;
    function rescueTokens(address token, address recipient) external;
    function setWhitelist(address manager, bool whitelisted) external;
    function transferOwnership(address owner) external;
}
