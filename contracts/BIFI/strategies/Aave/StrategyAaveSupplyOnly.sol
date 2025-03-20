// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/aave/IAaveV3Incentives.sol";
import "../../interfaces/aave/ILendingPool.sol";
import "../../interfaces/aave/IAaveToken.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

contract StrategyAaveSupplyOnly is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    address public aToken;
    address public lendingPool;
    address public incentivesController;

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
        return IERC20(aToken).balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(lendingPool, amount);
        ILendingPool(lendingPool).deposit(want, amount, address(this), 0);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            ILendingPool(lendingPool).withdraw(want, amount, address(this));
        }
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        if (amount > 0) {
            ILendingPool(lendingPool).withdraw(want, type(uint).max, address(this));
        }
    }

    function _claim() internal override {
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        IAaveV3Incentives(incentivesController).claimAllRewards(assets, address(this));
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != aToken, "!aToken");
    }
}
