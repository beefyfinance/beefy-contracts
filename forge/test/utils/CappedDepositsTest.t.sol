// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "forge-std/Test.sol";

import {CappedDeposits} from "../../../contracts/BIFI/utils/CappedDeposits.sol";

// create a mock vault with this modifier
contract TestVault is CappedDeposits {
    uint256 public depositedAmount;
    address public owner;

    function initialize(uint256 defaultCapacity, address _owner) public initializer {
        __CappedDeposits_init(defaultCapacity);
        owner = _owner;
    }

    function _canAdministrateVaultCapacity(address user) internal view override returns (bool) {
        return user == owner;
    }

    function balance() public view returns (uint256) {
        return depositedAmount;
    }

    function deposit(uint256 _amount) public cappedDepositsGuard(balance(), _amount) {
        depositedAmount += _amount;
    }
}

contract TemporaryCappedDepositsTest is Test {
    TestVault vault;
    address owner;
    address user1;
    address user2;

    function setUp() public {
        vault = new TestVault();
        owner = address(0x1);
        user1 = address(0x2);
        user2 = address(0x3);
    }

    function test_CappedDeposits_canDepositUntilMaxCapacityIsReached() public {
        // we set the capacity to 1000
        vault.initialize(1000, owner);

        assertEq(vault.balance(), 0);

        vault.deposit(100);
        vault.deposit(900);
        assertEq(vault.balance(), 1000);

        // now if we add more, it should revert
        console.log("should revert next");
        vm.expectRevert();
        vault.deposit(10);
        assertEq(vault.balance(), 1000);

        // now we change the capacity to 2000
        vm.prank(owner);
        vault.setVaultCapacity(2000);

        // and we can deposit again
        vault.deposit(10);
        assertEq(vault.balance(), 1010);
        vault.deposit(900);
        assertEq(vault.balance(), 1910);

        // but not too much
        console.log("should revert next");
        vm.expectRevert();
        vault.deposit(100);
        assertEq(vault.balance(), 1910);

        // now when capacity is zero, we can deposit as much as we want
        vm.prank(owner);
        vault.setVaultCapacity(0);
        vault.deposit(100);
        assertEq(vault.balance(), 2010);
        assertEq(vault.isVaultCapped(), false);
        assertEq(vault.vaultMaxCapacity(), 0);
    }

    function test_CappedDeposits_canOnlyUpdateCapacityIfOwner() public {
        // we set the capacity to 1000
        vault.initialize(1000, owner);
        assertEq(vault.vaultMaxCapacity(), 1000);

        // now we change the capacity to 2000
        vm.prank(owner);
        vault.setVaultCapacity(2000);
        assertEq(vault.vaultMaxCapacity(), 2000);

        // user1 trying to change the capacity should revert
        vm.prank(user1);
        vm.expectRevert();
        vault.setVaultCapacity(0);
        assertEq(vault.vaultMaxCapacity(), 2000);

        // user2 trying to change the capacity should revert
        vm.prank(user2);
        vm.expectRevert();
        vault.setVaultCapacity(123);
        assertEq(vault.vaultMaxCapacity(), 2000);
    }
}
