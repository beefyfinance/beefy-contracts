// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

contract BeSolidManager is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /**
     * @dev Beefy Contracts:
     * {keeper} - Address to manage a few lower risk features of the strat..
     */
    address public keeper;
    address public voter;

    event NewKeeper(address oldKeeper, address newKeeper);
    event NewVoter(address newVoter);

    /**
     * @dev Initializes the base strategy.
     * @param _keeper address to use as alternative owner.
     */
   constructor(
        address _keeper,
        address _voter
    ) {

        keeper = _keeper;
        voter = _voter;
    }

    // Checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // Checks that caller is either owner or keeper.
    modifier onlyVoter() {
        require(msg.sender == voter, "!voter");
        _;
    }

    /**
     * @dev Updates address of the strat keeper.
     * @param _keeper new keeper address.
     */
    function setKeeper(address _keeper) external onlyManager {
        emit NewKeeper( keeper, _keeper);
        keeper = _keeper;
    }

     function setVoter(address _voter) external onlyManager {
        emit NewVoter(_voter);
        voter = _voter;
    }
    
}
