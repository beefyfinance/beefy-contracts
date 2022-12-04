// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Prevent depositing too much into an experimental vault.
 *
 * There are sometimes where we're pushing an experimental vault. Or for a few different reasons, we might want to have a temporary cap on deposits.
 * The goal would be to have a reusable contract that lets strategies have a max cap.
 * This would prevent people from apeing $5M into something experimental.
 */
abstract contract CappedDeposits is Initializable {
    /**
     * @dev Default capacity per user
     */
    uint256 private _defaultCap;

    /**
     * @dev Capacity per user, overrides default capacity if > 0
     */
    mapping(address => uint256) private _userCap;

    /**
     * @dev Allow the owner to disable capacity checks altogether
     * used when the vault is considered safe to use
     */
    bool private _capEnabled;

    error CappedDeposits__CappacityReached(uint256 userCap, uint256 currentWantAmount, uint256 additionalWantAmount);
    error CappedDeposits__UnauthorizedAdminAction(address user);

    function __CappedDeposits_init(uint256 defaultCap) internal onlyInitializing {
        _defaultCap = defaultCap;
    }

    /**
     * Since we can't assume the security assumptions of the vault (using Ownable or OwnableUpgradeable), we delegate
     * the responsibility of checking if we can change the user capacity
     */
    function _canAdministrateCapacity(address user) internal view virtual returns (bool);

    /**
     * @dev Set the capacity for a user
     */
    function setUserCapacity(address user, uint256 capacity) external {
        if (!_canAdministrateCapacity(msg.sender)) {
            revert CappedDeposits__UnauthorizedAdminAction(msg.sender);
        }
        _userCap[user] = capacity;
    }

    /**
     * @dev Set the capacity for a user
     */
    function setCapacityEnabled(bool capEnabled) external {
        if (!_canAdministrateCapacity(msg.sender)) {
            revert CappedDeposits__UnauthorizedAdminAction(msg.sender);
        }
        _capEnabled = capEnabled;
    }

    /**
     * Reverts if user has reached capacity
     */
    function _checkCapacity(uint256 currentWantAmount, uint256 additionalWantAmount, address user) internal view {
        uint256 userCap = _userCap[user] == 0 ? _defaultCap : _userCap[user];
        if (currentWantAmount + additionalWantAmount > userCap) {
            revert CappedDeposits__CappacityReached(userCap, currentWantAmount, additionalWantAmount);
        }
    }

    modifier cappedDepositsGuard(uint256 currentWantAmount, uint256 additionalWantAmount, address user) {
        _checkCapacity(currentWantAmount, additionalWantAmount, user);

        _;
    }
}
