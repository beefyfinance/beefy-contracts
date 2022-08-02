// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./StrategyNewQuick.sol";
import "../Common/DelegateManagerCommon.sol";

contract StrategyNewQuickVoter is StrategyNewQuick, DelegateManagerCommon {

    constructor(
        address _want,
        address _rewardPool,
        address _quickConverter,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantRoute,
        address[] memory _outputToOldWantRoute,
        bytes32 _id,
        address _voter
    ) StrategyNewQuick(
        _want,
        _rewardPool,
        _quickConverter,
        _vault,
        _unirouter,
        _keeper,
        _strategist,
        _beefyFeeRecipient,
        _outputToNativeRoute,
        _outputToWantRoute,
        _outputToOldWantRoute
    ) DelegateManagerCommon(_id, _voter) public {}

    function beforeDeposit() external virtual override(StratManager, StrategyNewQuick) {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }
}
