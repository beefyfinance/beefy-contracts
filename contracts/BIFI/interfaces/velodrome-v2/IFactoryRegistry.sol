// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFactoryRegistry {
    error FallbackFactory();
    error InvalidFactoriesToPoolFactory();
    error PathAlreadyApproved();
    error PathNotApproved();
    error SameAddress();
    error ZeroAddress();

    event Approve(address indexed poolFactory, address indexed votingRewardsFactory, address indexed gaugeFactory);
    event Unapprove(address indexed poolFactory, address indexed votingRewardsFactory, address indexed gaugeFactory);
    event SetManagedRewardsFactory(address indexed _newRewardsFactory);

    /// @notice Approve a set of factories used in Velodrome Protocol.
    ///         Router.sol is able to swap any poolFactories currently approved.
    ///         Cannot approve address(0) factories.
    ///         Cannot aprove path that is already approved.
    ///         Each poolFactory has one unique set and maintains state.  In the case a poolFactory is unapproved
    ///             and then re-approved, the same set of factories must be used.  In other words, you cannot overwrite
    ///             the factories tied to a poolFactory address.
    ///         VotingRewardsFactories and GaugeFactories may use the same address across multiple poolFactories.
    /// @dev Callable by onlyOwner
    /// @param poolFactory .
    /// @param votingRewardsFactory .
    /// @param gaugeFactory .
    function approve(address poolFactory, address votingRewardsFactory, address gaugeFactory) external;

    /// @notice Unapprove a set of factories used in Velodrome Protocol.
    ///         While a poolFactory is unapproved, Router.sol cannot swap with pools made from the corresponding factory
    ///         Can only unapprove an approved path.
    ///         Cannot unapprove the fallback path (core v2 factories).
    /// @dev Callable by onlyOwner
    /// @param poolFactory .
    function unapprove(address poolFactory) external;

    /// @notice Factory to create free and locked rewards for a managed veNFT
    function managedRewardsFactory() external view returns (address);

    /// @notice Set the rewards factory address
    /// @dev Callable by onlyOwner
    /// @param _newManagedRewardsFactory address of new managedRewardsFactory
    function setManagedRewardsFactory(address _newManagedRewardsFactory) external;

    /// @notice Get the factories correlated to a poolFactory.
    ///         Once set, this can never be modified.
    ///         Returns the correlated factories even after an approved poolFactory is unapproved.
    function factoriesToPoolFactory(
        address poolFactory
    ) external view returns (address votingRewardsFactory, address gaugeFactory);

    /// @notice Get all PoolFactories approved by the registry
    /// @dev The same PoolFactory address cannot be used twice
    /// @return Array of PoolFactory addresses
    function poolFactories() external view returns (address[] memory);

    /// @notice Check if a PoolFactory is approved within the factory registry.  Router uses this method to
    ///         ensure a pool swapped from is approved.
    /// @param poolFactory .
    /// @return True if PoolFactory is approved, else false
    function isPoolFactoryApproved(address poolFactory) external view returns (bool);

    /// @notice Get the length of the poolFactories array
    function poolFactoriesLength() external view returns (uint256);
}
