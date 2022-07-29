// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./StrategyBeethovenxfBeets.sol";
import "../Common/DelegateManagerCommon.sol";

contract StrategyBeethovenxVoter is StrategyBeethovenxfBeets, DelegateManagerCommon {

    constructor(
        bytes32[] memory _balancerPoolIds,
        uint256 _chefPoolId,
        address _chef,
        address _input,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StrategyBeethovenxfBeets(
        _balancerPoolIds,
        _chefPoolId,
        _chef,
        _input,
        _vault,
        _unirouter,
        _keeper,
        _strategist,
        _beefyFeeRecipient
    ) DelegateManagerCommon(
        bytes32(0x62656574732e6574680000000000000000000000000000000000000000000000),
        address(0x5e1caC103F943Cd84A1E92dAde4145664ebf692A)
    ) public {}

    function beforeDeposit() external virtual override(StratManager, StrategyBeethovenxfBeets) {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }
}
