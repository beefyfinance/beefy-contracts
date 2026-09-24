// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Common/BaseAllToNativeFactoryStrat.sol";
import "./IPendle.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";

contract StrategyPendle is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    function initialize(
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer  {
        __BaseStrategy_init(_addresses, _rewards);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "Pendle";
    }

    function balanceOfPool() public pure override returns (uint) {
        return 0;
    }

    function _deposit(uint amount) internal override {}

    function _withdraw(uint amount) internal override {}

    function _emergencyWithdraw() internal override {}

    function _claim() internal override {
        IPendleMarket(want).redeemRewards(address(this));
    }

    function _verifyRewardToken(address token) internal view override {}

    function merklClaim(
        address claimer,
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        IMerklClaimer(claimer).claim(users, tokens, amounts, proofs);
    }
}