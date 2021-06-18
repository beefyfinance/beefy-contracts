// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma abicoder v1;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(
        uint256 _initialSupply,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _initialSupply);
    }
}