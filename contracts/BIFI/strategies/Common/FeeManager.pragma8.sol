// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./StratManager.pragma8.sol";

error FeeTooHigh();

abstract contract FeeManager is StratManager {
    uint constant public STRATEGIST_FEE = 112;
    uint constant public MAX_FEE = 1000;
    uint constant public MAX_CALL_FEE = 111;

    uint constant public WITHDRAWAL_FEE_CAP = 50;
    uint constant public WITHDRAWAL_MAX = 10000;

    uint public withdrawalFee = 10;

    uint public callFee = 111;
    uint public beefyFee = MAX_FEE - STRATEGIST_FEE - callFee;

    function setCallFee(uint256 _fee) public onlyManager {
        if (_fee <= MAX_CALL_FEE) revert FeeTooHigh();
        
        callFee = _fee;
        beefyFee = MAX_FEE - STRATEGIST_FEE - callFee;
    }

    function setWithdrawalFee(uint256 _fee) public onlyManager {
        if(_fee <= WITHDRAWAL_FEE_CAP) revert FeeTooHigh();

        withdrawalFee = _fee;
    }
}