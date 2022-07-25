// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./StratManager.sol";

abstract contract FeeManager is StratManager {
    uint constant public MAX_TOTAL_FEE = 95;
    uint constant public MAX_FEE = 1000;
    uint constant public MAX_STRAT_FEE = 112;
    uint constant public MAX_CALL_FEE = 111;

    uint constant public WITHDRAWAL_FEE_CAP = 50;
    uint constant public WITHDRAWAL_MAX = 10000;

    uint public withdrawalFee = 10;

    uint public totalFee = 95;
    uint public callFee = 111;
    uint public strategistFee = 112;
    uint public beefyFee = MAX_FEE - strategistFee - callFee;

    function setTotalFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_TOTAL_FEE, "!cap");

        totalFee = _fee;
    }

    function setCallFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_CALL_FEE, "!cap");

        callFee = _fee;
        beefyFee = MAX_FEE - strategistFee - callFee;
    }

    function setStrategistFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_STRAT_FEE, "!cap");

        strategistFee = _fee;
        beefyFee = MAX_FEE - strategistFee - callFee;
    }

    function setWithdrawalFee(uint256 _fee) public onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");

        withdrawalFee = _fee;
    }
}