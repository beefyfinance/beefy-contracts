// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev Prevent depositing too much into an experimental vault.
 *
 * There are sometimes where we're pushing an experimental vault. Or for a few different reasons, we might want to have a temporary cap on deposits.
 * The goal would be to have a reusable contract that lets strategies have a cap for the first x blocks of their existence.
 * This would prevent people from apeing $5M into something experimental.
 */
abstract contract TemporaryCappedDeposits is Initializable {
    /**
     * @dev Apply amount cap amount until this block number is reached
     * If set to 0, there is no cap.
     */
    uint256 private _capUntilBlock;

    /**
     * @dev Maximum want amount allowed to be deposited
     */
    uint256 private _capWantAmount;

    error TemporaryCappedDeposits__CappacityReached();

    function __TemporaryCappedDeposits_init(uint256 capUntilBlock, uint256 capWantAmount) internal onlyInitializing {
        _capWantAmount = capWantAmount;
        _capUntilBlock = capUntilBlock;
    }

    modifier cappedDepositsGuard(uint256 currentWantAmount, uint256 additionalWantAmount) {
        if (block.number < _capUntilBlock) {
            if (currentWantAmount + additionalWantAmount > _capWantAmount) {
                revert TemporaryCappedDeposits__CappacityReached();
            }
        }

        _;
    }
}
