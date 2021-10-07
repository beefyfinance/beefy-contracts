// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";

interface Vault {
    function proposeStrat(address _candidate) external;
    function upgradeStrat() external;
}

contract VaultOwnerSplit is Ownable {
    address public keeper;

    constructor(address _keeper) {
        keeper = _keeper;
    }

    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    function proposeStrat(address _vault, address _candidate) external onlyOwner {
        Vault(_vault).proposeStrat(_candidate);
    }

    function upgradeStrat(address _vault) external onlyManager {
        Vault(_vault).upgradeStrat();
    }

    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
    }
}