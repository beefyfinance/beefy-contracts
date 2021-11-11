// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./MaxiStratManager.sol";

abstract contract MaxiFeeManager is MaxiStratManager {
    uint constant public MAX_FEE_CAP = 50;
    uint constant public MAX_CALL_FEE = 10000;

    uint constant public WITHDRAWAL_FEE_CAP = 50;
    uint constant public WITHDRAWAL_MAX = 10000;

    uint public withdrawalFee = 5;

    uint public callFee = 50;

    function setCallFee(uint256 _fee) public onlyManager {
        require(_fee <= MAX_FEE_CAP, "!cap");

        callFee = _fee;
    }

    function setWithdrawalFee(uint256 _fee) public onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");

        withdrawalFee = _fee;
    }
}