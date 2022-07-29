// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./StrategyCakeBoostedLP.sol";
import "../Common/DelegateManagerCommon.sol";

contract StrategyCakeBoostedLPVoter is StrategyCakeBoostedLP, DelegateManagerCommon {

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _boostStaker,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route,
        bytes32 _id,
        address _voter
    ) StrategyCakeBoostedLP(
        _want,
        _poolId,
        _chef,
        _boostStaker,
        _vault,
        _unirouter,
        _keeper,
        _strategist,
        _beefyFeeRecipient,
        _outputToNativeRoute,
        _outputToLp0Route,
        _outputToLp1Route
    ) DelegateManagerCommon(_id, _voter) public {}

    function beforeDeposit() external virtual override(StratManager, StrategyCakeBoostedLP) {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }
}