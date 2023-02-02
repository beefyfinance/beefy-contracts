// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGnsStaking {
    function stakeTokens(uint256 _amount) external;
    function unstakeTokens(uint256 _amount) external;
    function harvest() external;
    function users(address _user) external view returns (
        uint256 stakedTokens,
        uint256 debtDai,
        uint256 stakedNftsCount,
        uint256 totalBoostTokens,
        uint256 harvestedRewardsDai
    );
}
