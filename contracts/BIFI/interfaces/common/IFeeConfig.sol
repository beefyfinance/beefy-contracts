// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFeeConfig {
    struct FeeCategory {
        uint256 total;
        uint256 beefy;
        uint256 call;
        uint256 strategist;
        string label;
        bool active;
    }
    function getFees() external view returns (FeeCategory memory);
    function stratFeeId(address strategy) external view returns (uint256);
    function setStratFeeId(uint256 feeId) external;
}
