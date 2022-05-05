// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./StrategyCommonChefLP.sol";
import "./DelegateManagerCommon.sol";

contract StrategyCommonChefLPVoter is StrategyCommonChefLP, DelegateManagerCommon {

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
        address[] memory _outputToLp1Route,
        bytes32 _id
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
    ) DelegateManagerCommon(_id) public {}

    function beforeDeposit() external virtual override(StratManager, StrategyCommonChefLP) {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }
}
