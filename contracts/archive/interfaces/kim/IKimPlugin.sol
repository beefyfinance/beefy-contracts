// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title The interface for the Algebra volatility oracle
/// @dev This contract stores timepoints and calculates statistical averages
interface IKimPlugin {
  /// @notice Returns data belonging to a certain timepoint
  /// @param index The index of timepoint in the array
  /// @dev There is more convenient function to fetch a timepoint: getTimepoints(). Which requires not an index but seconds
  /// @return initialized Whether the timepoint has been initialized and the values are safe to use
  /// @return blockTimestamp The timestamp of the timepoint
  /// @return tickCumulative The tick multiplied by seconds elapsed for the life of the pool as of the timepoint timestamp
  /// @return volatilityCumulative Cumulative standard deviation for the life of the pool as of the timepoint timestamp
  /// @return tick The tick at blockTimestamp
  /// @return averageTick Time-weighted average tick
  /// @return windowStartIndex Index of closest timepoint >= WINDOW seconds ago
  function timepoints(
    uint256 index
  )
    external
    view
    returns (
      bool initialized,
      uint32 blockTimestamp,
      int56 tickCumulative,
      uint88 volatilityCumulative,
      int24 tick,
      int24 averageTick,
      uint16 windowStartIndex
    );

  /// @notice Returns the index of the last timepoint that was written.
  /// @return index of the last timepoint written
  function timepointIndex() external view returns (uint16);

  /// @notice Returns the timestamp of the last timepoint that was written.
  /// @return timestamp of the last timepoint
  function lastTimepointTimestamp() external view returns (uint32);

  /// @notice Returns information about whether oracle is initialized
  /// @return true if oracle is initialized, otherwise false
  function isInitialized() external view returns (bool);

  /// @dev Reverts if a timepoint at or before the desired timepoint timestamp does not exist.
  /// 0 may be passed as `secondsAgo' to return the current cumulative values.
  /// If called with a timestamp falling between two timepoints, returns the counterfactual accumulator values
  /// at exactly the timestamp between the two timepoints.
  /// @dev `volatilityCumulative` values for timestamps after the last timepoint _should not_ be compared because they may differ due to interpolation errors
  /// @param secondsAgo The amount of time to look back, in seconds, at which point to return a timepoint
  /// @return tickCumulative The cumulative tick since the pool was first initialized, as of `secondsAgo`
  /// @return volatilityCumulative The cumulative volatility value since the pool was first initialized, as of `secondsAgo`
  function getSingleTimepoint(uint32 secondsAgo) external view returns (int56 tickCumulative, uint88 volatilityCumulative);

  /// @notice Returns the accumulator values as of each time seconds ago from the given time in the array of `secondsAgos`
  /// @dev Reverts if `secondsAgos` > oldest timepoint
  /// @dev `volatilityCumulative` values for timestamps after the last timepoint _should not_ be compared because they may differ due to interpolation errors
  /// @param secondsAgos Each amount of time to look back, in seconds, at which point to return a timepoint
  /// @return tickCumulatives The cumulative tick since the pool was first initialized, as of each `secondsAgo`
  /// @return volatilityCumulatives The cumulative volatility values since the pool was first initialized, as of each `secondsAgo`
  function getTimepoints(uint32[] memory secondsAgos) external view returns (int56[] memory tickCumulatives, uint88[] memory volatilityCumulatives);

  /// @notice Fills uninitialized timepoints with nonzero value
  /// @dev Can be used to reduce the gas cost of future swaps
  /// @param startIndex The start index, must be not initialized
  /// @param amount of slots to fill, startIndex + amount must be <= type(uint16).max
  function prepayTimepointsStorageSlots(uint16 startIndex, uint16 amount) external;

  /// @notice Returns fee from plugin
  /// @return fee The pool fee value in hundredths of a bip, i.e. 1e-6
  function getCurrentFee() external view returns (uint16 fee);

}
