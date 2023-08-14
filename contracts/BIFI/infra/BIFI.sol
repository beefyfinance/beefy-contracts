// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";

contract BIFI is ERC20 {

    constructor(address treasury) ERC20("Beefy", "BIFI")  {
        _mint(treasury, 80_000 ether);
    }

}