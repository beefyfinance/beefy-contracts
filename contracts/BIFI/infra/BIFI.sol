// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";

contract BIFI is ERC20 {

    constructor() ERC20("Beefy", "BIFI")  {
        _mint(msg.sender, 80_000 ether);
    }

}