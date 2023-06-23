// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract CascadingAccessControl is AccessControlUpgradeable {

    modifier atLeastRole(bytes32 _role) {
        _atLeastRole(_role);
        _;
    }

    /**
     * @dev Checks cascading role privileges to ensure that caller has at least role {_role}.
     * Any higher privileged role should be able to perform all the functions of any lower privileged role.
     * This is accomplished using the {cascadingAccess} array that lists all roles from most privileged
     * to least privileged.
     * @param _role - The role in bytes from the keccak256 hash of the role name
     */
    function _atLeastRole(bytes32 _role) internal view {
        bytes32[] memory _cascadingAccessRoles = cascadingAccessRoles();
        uint256 numRoles = _cascadingAccessRoles.length;
        bool specifiedRoleFound = false;
        bool senderHighestRoleFound = false;

        // {_role} must be found in the {cascadingAccessRoles} array.
        // Also, msg.sender's highest role index <= specified role index.
        for (uint256 i = 0; i < numRoles;) {
            if (!senderHighestRoleFound && hasRole(_cascadingAccessRoles[i], msg.sender)) {
                senderHighestRoleFound = true;
            }
            if (_role == _cascadingAccessRoles[i]) {
                specifiedRoleFound = true;
                break;
            }
            unchecked { ++i; }
        }

        require(specifiedRoleFound && senderHighestRoleFound, "Unauthorized access");
    }

    /**
     * @dev Returns an array of all the relevant roles arranged in descending order of privilege.
     * Subclasses should override this to specify their unique roles arranged in the correct
     * order, for example, [SUPER-ADMIN, ADMIN, GUARDIAN, STRATEGIST].
     */
    function cascadingAccessRoles() public view virtual returns (bytes32[] memory);
}