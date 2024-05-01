// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title Beefy Oracle Errors
/// @author Beefy, @kexley
/// @notice Error list for Beefy Oracles
contract BeefyOracleErrors {

    /// @dev No response from the Chainlink feed
    error NoAnswer();

    /// @dev No price for base token
    /// @param token Base token
    error NoBasePrice(address token);

    /// @dev Token is not present in the pair
    /// @param token Input token
    /// @param pair Pair token
    error TokenNotInPair(address token, address pair);

    /// @dev Array length is not correct
    error ArrayLength();

}
