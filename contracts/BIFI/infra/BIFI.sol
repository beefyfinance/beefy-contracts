// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract BIFI is ERC20, ERC20Permit {

    constructor(address treasury) ERC20("Beefy", "BIFI") ERC20Permit("Beefy")  {
        _mint(treasury, 80_000 ether);
    }

}