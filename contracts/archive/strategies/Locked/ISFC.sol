// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISFC {
    function delegate(uint256 toValidatorID) external payable;
    function relockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external;
    function lockStake(uint256 toValidatorID, uint256 lockupDuration, uint256 amount) external;
    function undelegate(uint256 toValidatorID, uint256 wrID, uint256 amount) external;
    function unlockStake(uint256 toValidatorID, uint256 amount) external returns (uint256);
    function withdraw(uint256 toValidatorID, uint256 wrID) external;
    function claimRewards(uint256 toValidatorID) external;
    function getLockedStake(address delegator, uint256 toValidatorID) external view returns (uint256);
    function getUnlockedStake(address delegator, uint256 toValidatorID) external view returns (uint256);
    function pendingRewards(address delegator, uint256 toValidatorID) external view returns (uint256);
    function getLockupInfo(address delegator, uint256 toValidatorID) external view returns ( uint256 lockedStake, uint256 fromEpoch, uint256 endTime, uint256 duration);
    function getWithdrawalRequest(address delegator, uint256 toValidatorID, uint256 wrID) external view returns (uint256 epoch, uint256 time, uint256 amount);
}