// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

abstract contract ManageableUpgradeable is Initializable, ContextUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    EnumerableSetUpgradeable.AddressSet private _managers;

    event ManagersUpdated(address[] users_, address status_);

    /* solhint-disable func-name-mixedcase */
    /**
     * @dev Initializes the contract setting the deployer as the only manager.
     */
    function __Manageable_init() internal onlyInitializing {
        /* solhint-enable func-name-mixedcase */
        __Context_init_unchained();
        __Manageable_init_unchained();
    }

    /* solhint-disable func-name-mixedcase */
    function __Manageable_init_unchained() internal onlyInitializing {
        /* solhint-enable func-name-mixedcase */
        _setManager(_msgSender(), true);
    }

    /**
     * @dev Throws if called by any account other than the manager.
     */
    modifier onlyManager() {
        require(_managers.contains(msg.sender), "!manager");
        _;
    }

    function setManagers(address[] memory managers_, bool status_) external onlyManager {
        for (uint256 managerIndex = 0; managerIndex < managers_.length; managerIndex++) {
            _setManager(managers_[managerIndex], status_);
        }
    }

    function _setManager(address manager_, bool status_) internal {
        if (status_) {
            _managers.add(manager_);
        } else {
            // Must be at least 1 manager.
            require(_managers.length() > 1, "!(managers > 1)");
            _managers.remove(manager_);
        }
    }

    uint256[49] private __gap;
}
