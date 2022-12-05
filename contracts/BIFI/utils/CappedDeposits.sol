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
     * @dev vault capacity in want token amount
     * Capacity checks are disabled if set to 0
     */
    uint256 private _totalWantCap;

    error CappedDeposits__CappacityReached(
        uint256 currentWantAmount, uint256 additionalWantAmount, uint256 totalWantCap
    );
    error CappedDeposits__UnauthorizedAdminAction(address user);

    function __CappedDeposits_init(uint256 totalWantCap) internal onlyInitializing {
        _totalWantCap = totalWantCap;
    }

    /**
     * Since we can't assume the security assumptions of the vault (using Ownable or OwnableUpgradeable), we delegate
     * the responsibility of checking if we can change the user capacity
     */
    function _canAdministrateVaultCapacity(address user) internal view virtual returns (bool);

    /**
     * @dev Set the total vault capacity
     */
    function setVaultCapacity(uint256 wantAmount) external {
        if (!_canAdministrateVaultCapacity(msg.sender)) {
            revert CappedDeposits__UnauthorizedAdminAction(msg.sender);
        }
        _totalWantCap = wantAmount;
    }

    /**
     * @dev Find out if capacity limit is enabled
     */
    function isVaultCapped() public view returns (bool) {
        return _totalWantCap > 0;
    }

    /**
     * @dev Find out the capacity
     */
    function getVaultTotalCappacity() public view returns (uint256) {
        return _totalWantCap;
    }

    /**
     * Reverts if user has reached capacity
     */
    function _checkCapacity(uint256 currentWantAmount, uint256 additionalWantAmount) internal view {
        if (isVaultCapped() && currentWantAmount + additionalWantAmount > _totalWantCap) {
            revert CappedDeposits__CappacityReached(currentWantAmount, additionalWantAmount, _totalWantCap);
        }
    }

    modifier cappedDepositsGuard(uint256 currentWantAmount, uint256 additionalWantAmount) {
        _checkCapacity(currentWantAmount, additionalWantAmount);

        _;
    }
}
