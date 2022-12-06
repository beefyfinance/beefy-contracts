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
    uint256 public vaultMaxCapacity;

    event CappedDeposits__CappacityUpdated(uint256 previousCapacity, uint256 vaultMaxCapacity);

    error CappedDeposits__CappacityReached(
        uint256 currentWantAmount, uint256 additionalWantAmount, uint256 vaultMaxCapacity
    );
    error CappedDeposits__UnauthorizedAdminAction(address user);

    function __CappedDeposits_init(uint256 _vaultMaxCapacity) internal onlyInitializing {
        vaultMaxCapacity = _vaultMaxCapacity;
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
        uint256 previousCapacity = vaultMaxCapacity;
        vaultMaxCapacity = wantAmount;
        emit CappedDeposits__CappacityUpdated(previousCapacity, vaultMaxCapacity);
    }

    /**
     * @dev Find out if capacity limit is enabled
     */
    function isVaultCapped() public view returns (bool) {
        return vaultMaxCapacity > 0;
    }

    /**
     * Reverts if user has reached capacity
     */
    function _checkCapacity(uint256 currentWantAmount, uint256 additionalWantAmount) internal view {
        if (isVaultCapped() && currentWantAmount + additionalWantAmount > vaultMaxCapacity) {
            revert CappedDeposits__CappacityReached(currentWantAmount, additionalWantAmount, vaultMaxCapacity);
        }
    }

    modifier cappedDepositsGuard(uint256 currentWantAmount, uint256 additionalWantAmount) {
        _checkCapacity(currentWantAmount, additionalWantAmount);

        _;
    }
}
