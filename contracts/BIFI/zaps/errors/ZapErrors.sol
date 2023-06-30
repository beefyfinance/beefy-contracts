// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract ZapErrors {
    error InsignificantAmount();
    error NotWETH();
    error WrongToken(); // Beefy: desired token not present in liquidity pair.
    error InsufficientAmount();
    error IncompatiblePair();
    error ReservesTooLow();
    error TransferFail();
}