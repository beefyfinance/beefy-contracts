// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./StrategyXSyrup.sol";
import "../Common/DelegateManagerCommon.sol";

contract StrategyXSyrupVoter is StrategyXSyrup, DelegateManagerCommon {

    constructor(
        address _want,
        address _xWant,
        uint256 _pid,
        address _xChef,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantRoute,
        bytes32 _id,
        address _voter
    ) StrategyXSyrup(
        _want,
        _xWant,
        _pid,
        _xChef,
        _vault,
        _unirouter,
        _keeper,
        _strategist,
        _beefyFeeRecipient,
        _outputToNativeRoute,
        _outputToWantRoute
    ) DelegateManagerCommon(_id, _voter) public {}

    function beforeDeposit() external virtual override(StratManager, StrategyXSyrup) {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }
}
