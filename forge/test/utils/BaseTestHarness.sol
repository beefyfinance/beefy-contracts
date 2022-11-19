// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {DSTest, console, Vm} from "forge-std/Test.sol";

import {IERC20Like} from "../interfaces/IERC20Like.sol";

contract BaseTestHarness is DSTest {
    // Api to modify test vm state.
    Vm internal constant FORGE_VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /*             */
    /* Forge Hacks */
    /*             */

    function modifyBalance(address token_, address user_, uint256 amount_) internal returns (uint256 slot_) {
        IERC20Like erc20 = IERC20Like(token_);
        bool found;
        for (uint256 i = 0; i < 10; i++) {  
            // Get before value in case the slot is wrong, so can restore the value.
            bytes32 beforeValue = FORGE_VM.load(address(token_), keccak256(abi.encode(user_, slot_)));
            
            // Modify storage slot.
            FORGE_VM.store(address(token_), keccak256(abi.encode(user_, slot_)), bytes32(amount_));

            uint256 balance = erc20.balanceOf(user_);
            
            if (balance == amount_) {
                found = true;
                break;
            }

            // Restore value.
            FORGE_VM.store(address(token_), keccak256(abi.encode(user_, slot_)), beforeValue);
            slot_ += 1;
        }

        if (!found) {
            assertTrue(false, "Never found storage slot to modify for ERC20 balance hack.");
        }
    }

    function modifyBalanceWithKnownSlot(address token_, address user_, uint256 amount_, uint256 slot) internal {
        FORGE_VM.store(address(token_), keccak256(abi.encode(user_, slot)), bytes32(amount_));
    }

    /**
     * @dev Shifts block.timestamp and block.number ahead.
     * @param seconds_ to shift block.timestamp and block.number ahead.
     */
    function shift(uint256 seconds_) public {
        console.log("Shifting forward seconds", seconds_);
        FORGE_VM.warp(block.timestamp + seconds_);
        FORGE_VM.roll(block.number + getApproximateBlocksFromSeconds(seconds_));
    }

    /**
     * @dev Shifts block.timestamp and block.number ahead.
     * @param seconds_ to shift block.timestamp and block.number ahead.
     */
    function getApproximateBlocksFromSeconds(uint256 seconds_) public pure returns (uint256 blocks_) {
        uint256 secondsPerBlock = 14;
        return seconds_ / secondsPerBlock;
    }

    /*               */
    /* General Utils */
    /*               */

    function compareStrings(string memory a_, string memory b_) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a_))) == keccak256(abi.encodePacked((b_))));
    }
}
