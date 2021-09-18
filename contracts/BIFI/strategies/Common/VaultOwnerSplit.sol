// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";

interface Vault {
    function proposeStrat(address _candidate) external;
    function upgradeStrat() external;
}

contract VaultOwnerSplit is Ownable {
    address public keeper;
    address public vault;

    constructor(address _keeper, address _vault) {
        keeper = _keeper;
        vault = _vault;
    }

    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    function proposeStrat(address _candidate) external onlyOwner {
        Vault(vault).proposeStrat(_candidate);
    }

    function upgradeStrat() external onlyManager {
        Vault(vault).upgradeStrat();
    }

    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
    }
}