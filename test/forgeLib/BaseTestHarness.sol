// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import {DSTest} from "./test.sol";
import {Vm} from "./Vm.sol";
import {console} from "./console.sol";

interface ERC20Like {
    function balanceOf(address account_) external view returns (uint256 balance_);
}

contract BaseTestHarness is DSTest {
    // Api to modify test vm state.
    Vm internal constant FORGE_VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /*             */
    /* Forge Hacks */
    /*             */

    function erc20MintHack(
        ERC20Like token_,
        address account_,
        uint256 slot_,
        uint256 amountToMint_
    ) public {
        uint256 currentBalance = token_.balanceOf(account_);
        uint256 newBalance = currentBalance + amountToMint_;
        FORGE_VM.store(address(token_), keccak256(abi.encode(account_, slot_)), bytes32(newBalance));
    }

    /**
     * @dev Shifts block.timestamp and block.number ahead.
     * @param seconds_ to shift block.timestamp and block.number ahead.
     */
    function shift(uint256 seconds_) public {
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
