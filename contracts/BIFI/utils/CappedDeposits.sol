// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @dev Prevent depositing too much into an experimental vault.
 *
 * There are sometimes where we're pushing an experimental vault. Or for a few different reasons, we might want to have a temporary cap on deposits.
 * The goal would be to have a reusable contract that lets strategies have a max cap.
 * This would prevent people from apeing $5M into something experimental.
 */
abstract contract CappedDeposits is Initializable, OwnableUpgradeable {
    /**
     * @dev capacity in want token amount
     * Capacity checks are disabled if set to 0
     */
    uint256 public maxCapacity;

    /// @notice Event emitted when the capacity is updated
    event CappedDeposits__CappacityUpdated(uint256 previousCapacity, uint256 maxCapacity);

    /// @notice Error sent when the user tries to deposit more than the contract capacity
    error CappedDeposits__CappacityReached(uint256 currentAmount, uint256 additionalAmount, uint256 maxCapacity);

    function __CappedDeposits_init(uint256 _maxCapacity) internal onlyInitializing {
        maxCapacity = _maxCapacity;
        emit CappedDeposits__CappacityUpdated(0, _maxCapacity);
    }

    /**
     * @dev Set the total vault capacity
     */
    function setMaxCapacity(uint256 _maxCapacity) external {
        _checkOwner();
        uint256 previousCapacity = maxCapacity;
        maxCapacity = _maxCapacity;
        emit CappedDeposits__CappacityUpdated(previousCapacity, _maxCapacity);
    }

    /**
     * @dev Find out if capacity limit is enabled
     */
    function isCapped() public view returns (bool) {
        return maxCapacity > 0;
    }

    /**
     * Reverts if user has reached capacity
     */
    function _checkCapacity(uint256 currentAmount, uint256 additionalAmount) internal view {
        if (isCapped() && currentAmount + additionalAmount > maxCapacity) {
            revert CappedDeposits__CappacityReached(currentAmount, additionalAmount, maxCapacity);
        }
    }

    modifier cappedDepositsGuard(uint256 currentAmount, uint256 additionalAmount) {
        _checkCapacity(currentAmount, additionalAmount);

        _;
    }
}
