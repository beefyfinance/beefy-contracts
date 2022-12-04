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

    function balance() public view returns (uint256) {
        return depositedAmount;
    }

    function deposit(uint256 _amount) public cappedDepositsGuard(balance(), _amount, msg.sender) {
        depositedAmount += _amount;
    }
}

contract TemporaryCappedDepositsTest is Test {
    TestVault vault;

    function setUp() public {
        vault = new TestVault();
    }

    function test_TemporaryCappedDeposits_canDepositAnyAmountIfBlockIsZero() public {
        assertEq(block.number, 1, "block number should be 1 when testing");

        // we set a block limit at 0, so we can deposit any amount from now on
        vault.initialize(0, 1000);

        assertEq(vault.balance(), 0);

        vault.deposit(100);
        vault.deposit(900);
        assertEq(vault.balance(), 1000);

        vault.deposit(1);
        assertEq(vault.balance(), 1001);

        vault.deposit(900);
        assertEq(vault.balance(), 1901);
    }

    function test_TemporaryCappedDeposits_canDepositAnyAmountIfBothParamsAreZero() public {
        assertEq(block.number, 1, "block number should be 1 when testing");

        // we set a block limit at 0, so we can deposit any amount from now on
        vault.initialize(0, 0);

        assertEq(vault.balance(), 0);

        vault.deposit(100);
        vault.deposit(900);
        assertEq(vault.balance(), 1000);

        vault.deposit(1);
        assertEq(vault.balance(), 1001);

        vault.deposit(900);
        assertEq(vault.balance(), 1901);
    }

    function test_TemporaryCappedDeposits_canDepositUpUntilWantLimitWhenBlockIsNonZero() public {
        assertEq(block.number, 1, "block number should be 1 when testing");

        // up until block 100, we can only deposit 1000 want tokens
        vault.initialize(100, 1000);

        assertEq(vault.balance(), 0);

        vault.deposit(100);
        vault.deposit(900);
        assertEq(vault.balance(), 1000);

        // now if we add more, it should revert
        console.log("should revert next");
        vm.expectRevert();
        vault.deposit(10);
        assertEq(vault.balance(), 1000);

        // if block advances, we can deposit more
        vm.roll(101);

        vault.deposit(10);
        assertEq(vault.balance(), 1010);
    }
}
