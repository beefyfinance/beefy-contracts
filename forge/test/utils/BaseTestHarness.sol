// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test, console, Vm} from "forge-std/Test.sol";

import {IERC20Like} from "../interfaces/IERC20Like.sol";

contract BaseTestHarness is Test {
    /*             */
    /* Forge Hacks */
    /*             */

    function modifyBalance(address token_, address user_, uint256 amount_) internal returns (uint256 slot_) {
        deal(token_, user_, amount_);
    }

    function modifyBalanceWithKnownSlot(address token_, address user_, uint256 amount_, uint256 slot) internal {
        vm.store(address(token_), keccak256(abi.encode(user_, slot)), bytes32(amount_));
    }

    /**
     * @dev Shifts block.timestamp and block.number ahead.
     * @param seconds_ to shift block.timestamp and block.number ahead.
     */
    function shift(uint256 seconds_) public {
        console.log("Shifting forward seconds", seconds_);
        vm.warp(block.timestamp + seconds_);
        vm.roll(block.number + getApproximateBlocksFromSeconds(seconds_));
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
