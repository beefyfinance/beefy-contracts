// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.6.0;

import "./StrategyCommonRewardPoolLP.sol";

contract StrategyCommonRewardPoolLPPolygon is StrategyCommonRewardPoolLP {
    constructor(
        address _want,
        address _rewardPool,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route,
        uint _callFee
    ) StrategyCommonRewardPoolLP(
        _want,
        _rewardPool,
        _vault,
        _unirouter,
        _keeper,
        _strategist,
        _beefyFeeRecipient,
        _outputToNativeRoute,
        _outputToLp0Route,
        _outputToLp1Route
    ) public {
        _setCallFee(_callFee);
    }

    function _setCallFee(uint _fee) internal {
        this.setCallFee(_fee);
    }
}
