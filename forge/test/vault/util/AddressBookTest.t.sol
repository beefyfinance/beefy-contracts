// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import { Test } from "forge-std/Test.sol";
import { AddressBook } from "./AddressBook.sol";


contract AddressBookTest is Test {

    AddressBook ab;

    function setUp() public {
        ab = new AddressBook();
    }

    function test_BeefyPlatformConfig_ethereum() external {
        AddressBook.BeefyPlatform memory config = ab.getBeefyPlatformConfig("ethereum");
        
        assertEq(config.keeper, 0x4fED5491693007f0CD49f4614FFC38Ab6A04B619, "keeper");
        assertEq(config.strategyOwner, 0x1c9270ac5C42E51611d7b97b1004313D52c80293, "strategyOwner");
        assertEq(config.vaultOwner, 0x5B6C5363851EC9ED29CB7220C39B44E1dd443992, "vaultOwner");
    }

    function test_BeefyPlatformConfig_bsc() external {
        AddressBook.BeefyPlatform memory config = ab.getBeefyPlatformConfig("bsc");
        
        assertEq(config.keeper, 0x4fED5491693007f0CD49f4614FFC38Ab6A04B619, "keeper");
        assertEq(config.strategyOwner, 0x65CF7E8C0d431f59787D07Fa1A9f8725bbC33F7E, "strategyOwner");
        assertEq(config.vaultOwner, 0xA2E6391486670D2f1519461bcc915E4818aD1c9a, "vaultOwner");
    }
}