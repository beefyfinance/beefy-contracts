// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/aave/IAaveV3Incentives.sol";
import "../../interfaces/aave/ILendingPool.sol";
import "../../interfaces/aave/IAaveToken.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";

/// @title StrategyAaveSupplyOnly
/// @notice This strategy is used to supply liquidity to Aave and earn rewards. Fees are charged on both rewards and interest.
/// @dev If using as a new implementation for an existing strategy, the old strategy MUST be panicked first.
/// Otherwise the stored balance will not be updated correctly.
contract StrategyAaveSupplyOnly is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    address public aToken;
    address public lendingPool;
    address public incentivesController;

    uint256 storedBalance;

    function initialize(
        address _aToken,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);
        aToken = _aToken;
        lendingPool = IAaveToken(aToken).POOL();
        incentivesController = IAaveToken(aToken).getIncentivesController();
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "Aave";
    }

    function balanceOfPool() public view override returns (uint) {
        return storedBalance;
    }

    function _deposit(uint amount) internal override {
        storedBalance += amount;
        IERC20(want).forceApprove(lendingPool, amount);
        ILendingPool(lendingPool).deposit(want, amount, address(this), 0);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            storedBalance -= amount;
            ILendingPool(lendingPool).withdraw(want, amount, address(this));
        }
    }

    function _emergencyWithdraw() internal override {
        storedBalance = 0;
        if (IERC20(aToken).balanceOf(address(this)) > 0) {
            ILendingPool(lendingPool).withdraw(want, type(uint).max, address(this));
        }
    }

    function _claim() internal override {
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        IAaveV3Incentives(incentivesController).claimAllRewards(assets, address(this));
    }

    function _swapRewardsToNative() internal override {
        uint256 aTokenBal = IERC20(aToken).balanceOf(address(this));
        if (aTokenBal > storedBalance) {
            uint256 amount = aTokenBal - storedBalance;
            ILendingPool(lendingPool).withdraw(want, amount, address(this));
            _swap(want, native, amount);
        }
        super._swapRewardsToNative();
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != aToken, "!aToken");
    }

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
