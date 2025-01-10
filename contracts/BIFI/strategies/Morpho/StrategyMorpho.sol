// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin-4/contracts/interfaces/IERC4626.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

contract StrategyMorpho is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IERC4626 public morphoVault;

    function initialize(
        address _morphoVault,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);
        morphoVault = IERC4626(_morphoVault);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "Morpho";
    }

    function balanceOfPool() public view override returns (uint) {
        return morphoVault.convertToAssets(morphoVault.balanceOf(address(this)));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(morphoVault), amount);
        morphoVault.deposit(amount, address(this));
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            morphoVault.withdraw(amount, address(this), address(this));
        }
    }

    function _emergencyWithdraw() internal override {
        uint bal = morphoVault.balanceOf(address(this));
        if (bal > 0) {
            morphoVault.redeem(bal, address(this), address(this));
        }
    }

    function _claim() internal override {}

    function _verifyRewardToken(address token) internal view override {
        require(token != address(morphoVault), "!morphoVault");
    }

    // Morpho vaults can have `want` as reward, timelocked
    function addWantAsReward() external onlyOwner {
        rewards.push(want);
    }

}