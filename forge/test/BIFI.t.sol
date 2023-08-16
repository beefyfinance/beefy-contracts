// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../node_modules/forge-std/src/Test.sol";
import "../../contracts/BIFI/infra/BIFI.sol";

contract BIFITest is Test {

    function test_mint() public {
        BIFI bifi = new BIFI(address(this));
        assertEq(bifi.totalSupply(), 80_000*1e18);
        assertEq(bifi.balanceOf(address(this)), 80_000*1e18);
    }

}