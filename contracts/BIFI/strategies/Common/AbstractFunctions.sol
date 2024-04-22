// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title Abstract functions
/// @author Beefy, @kexley
/// @notice Basic functions to be overridden by child contracts
abstract contract AbstractFunctions {

    /// @notice Balance of want tokens in the underlying platform
    /// @dev Should be overridden in child
    function balanceOfPool() public view virtual returns (uint256);

    /// @notice Rewards available to be claimed by the strategy
    /// @dev Should be overridden in child
    function rewardsAvailable() external view virtual returns (uint256);

    /// @notice Call rewards in native token that the harvest caller could claim
    /// @dev Should be overridden in child
    function callReward() external view virtual returns (uint256);

    /// @dev Deposit want tokens to the underlying platform
    /// Should be overridden in child
    /// @param _amount Amount to deposit to the underlying platform
    function _deposit(uint256 _amount) internal virtual;

    /// @dev Withdraw want tokens from the underlying platform
    /// Should be overridden in child
    /// @param _amount Amount to withdraw from the underlying platform
    function _withdraw(uint256 _amount) internal virtual;

    /// @dev Withdraw all want tokens from the underlying platform
    /// Should be overridden in child
    function _emergencyWithdraw() internal virtual;

    /// @dev Claim reward tokens from the underlying platform
    /// Should be overridden in child
    function _claim() internal virtual;

    /// @dev Get the amounts of native that should be swapped to the corresponding depositTokens
    /// Should be overridden in child
    /// @return depositAmounts Amounts in native to swap
    function _getDepositAmounts() internal view virtual returns (uint256[] memory depositAmounts);

    /// @dev Add liquidity to the underlying platform using depositTokens to create the want token
    /// Should be overridden in child
    function _addLiquidity() internal virtual;

    /// @dev Revert if the reward token is one of the critical tokens used by the strategy
    /// Should be overridden in child
    function _verifyRewardToken(address _token) internal view virtual;
}
