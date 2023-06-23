// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./CascadingAccessControl.sol";

import "../../interfaces/beefy/IBeefyVaultV8.sol";

contract StratManager is CascadingAccessControl, PausableUpgradeable {

    struct CommonAddresses {
        address vault;
        address timelock;
        address dev;
        address guardian;
        address strategist;
        address harvester;
    }

    bytes32 internal constant ADMIN = keccak256("ADMIN");
    bytes32 internal constant GUARDIAN = keccak256("GUARDIAN");
    bytes32 internal constant STRATEGIST = keccak256("STRATEGIST");
    bytes32 internal constant HARVESTER = keccak256("HARVESTER");

    bytes32[] private _cascadingAccessRoles = [
        bytes32(0),
        ADMIN,
        GUARDIAN,
        STRATEGIST,
        HARVESTER
    ];

    // common addresses for the strategy
    IBeefyVaultV8 public vault;

    /**
     * @dev Initializer function for the strategy manager. Grants roles to appropriate addresses.
     * @param _commonAddresses struct of addresses that are common across multiple strategies.
     */
    function __StratManager_init(CommonAddresses calldata _commonAddresses) internal onlyInitializing {
        __Pausable_init();
        vault = IBeefyVaultV8(_commonAddresses.vault);

        _grantRole(_cascadingAccessRoles[0], _commonAddresses.timelock);
        _grantRole(_cascadingAccessRoles[1], _commonAddresses.dev);
        _grantRole(_cascadingAccessRoles[2], _commonAddresses.guardian);
        _grantRole(_cascadingAccessRoles[3], _commonAddresses.strategist);
        _grantRole(_cascadingAccessRoles[4], _commonAddresses.harvester);
    }

    function cascadingAccessRoles() public view override returns (bytes32[] memory) {
        return _cascadingAccessRoles;
    }

    function beforeDeposit() external virtual {}
}