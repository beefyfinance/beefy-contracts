// SPDX-License-Identifier: MIT

pragma solidity ^0.5.0;

import "@openzeppelin-2/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-2/contracts/token/ERC20/ERC20Detailed.sol";

contract TestToken is ERC20, ERC20Detailed {
    constructor(
        uint256 initialSupply,         
        string memory _name, 
        string memory _symbol
    ) ERC20Detailed(_name, _symbol, 18) public {
        _mint(msg.sender, initialSupply);
    }
}