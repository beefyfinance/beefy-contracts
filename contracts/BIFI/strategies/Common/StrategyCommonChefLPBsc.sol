// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../Common/StrategyCommonChefLP.sol";
import "../../utils/GasThrottler.sol";

contract StrategyCommonChefLPBsc is StrategyCommonChefLP, GasThrottler {

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route
    ) StrategyCommonChefLP(
        _want,
        _poolId,
        _chef,
        _vault,
        _unirouter,
        _keeper,
        _strategist,
        _beefyFeeRecipient,
        _outputToNativeRoute,
        _outputToLp0Route,
        _outputToLp1Route
    ) public {}

   function harvest() external override whenNotPaused gasThrottle {
        _harvest(nullAddress);
    }
}
