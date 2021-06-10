// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "../strategies/Cake/StrategyCakeSmart.sol";

contract ExposedStrategyCakeSmart is StrategyCakeSmart {
    constructor(address _vault, uint256 _approvalDelay) StrategyCakeSmart(_vault, _approvalDelay) {}

    function _updatePoolInfo(uint8 poolId) external  {
        updatePoolInfo(poolId);
    }
}