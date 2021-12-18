// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

interface IMultiFeeDistributer {
    struct RewardData {
        address token;
        uint256 amount;
    }

    function claimableRewards(address account) external view returns (RewardData[] memory rewards);
    function exit() external;
}