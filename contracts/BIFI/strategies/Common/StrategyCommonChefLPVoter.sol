// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./StrategyCommonChefLP.sol";
import "./DelegateManagerCommon.sol";

contract StrategyCommonChefLPVoter is StrategyCommonChefLP, DelegateManagerCommon {

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        CommonAddresses memory _commonAddresses,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route,
        bytes32 _id,
        address _voter
    ) StrategyCommonChefLP(
        _want,
        _poolId,
        _chef,
        _commonAddresses,
        _outputToNativeRoute,
        _outputToLp0Route,
        _outputToLp1Route
    ) DelegateManagerCommon(_id, _voter) {}

    function beforeDeposit() external virtual override(StratFeeManager, StrategyCommonChefLP) {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }
}
