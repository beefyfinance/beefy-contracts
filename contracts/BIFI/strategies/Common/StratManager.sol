// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract StratManager is Ownable, Pausable {
    /**
     * @dev Beefy Contracts:
     * {keeper} - Address used as an extra owner. Should be a community multisig.
     * {strategist} - Address of the strategy author/deployer where strategist fee will go.
     * {vault} - Address of the vault that controls the strategy's funds.
     */
    address public keeper;
    address public strategist;

    /**
     * @dev Initializes the base strategy.
     * @param _keeper address to use as alternative owner.
     * @param _strategist address where strategist fees go.
     */
    constructor(        
        address _keeper, 
        address _strategist
    ) public {
        keeper = _keeper;
        strategist = _strategist;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // verifies that the caller is not a contract.
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "!EOA");
        _;
    }

    /**
     * @dev Updates address of the strat keeper.
     * @param _keeper new keeper address.
     */
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
    }

    /**
     * @dev Updates address where strategist fee earnings will go.
     * @param _strategist new strategist address.
     */
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
    }
}