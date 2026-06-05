// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin-5/contracts/interfaces/IERC4626.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

interface IStakeDaoVault is IERC4626 {
    function claim(address[] calldata tokens, address receiver) external returns (uint256[] memory);
    function getRewardTokens() external view returns (address[] memory);
    function ACCOUNTANT() external view returns (address);
    function gauge() external view returns (address);
}

interface IStakeDaoAccountant {
    function claim(address[] calldata _gauges, bytes[] calldata harvestData) external;
}

contract StrategyStakeDaoV2 is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IStakeDaoVault public sdVault;
    IStakeDaoAccountant public accountant;
    address[] public sdVaultRewards;
    address[] public harvestGauges;
    bytes[] public harvestData;

    function initialize(
        address _sdVault,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        sdVault = IStakeDaoVault(_sdVault);
        accountant = IStakeDaoAccountant(sdVault.ACCOUNTANT());
        sdVaultRewards = sdVault.getRewardTokens();
        harvestGauges.push(sdVault.gauge());
        harvestData.push(new bytes(0));

        __BaseStrategy_init(_addresses, _rewards);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "StakeDaoV2";
    }

    function balanceOfPool() public view override returns (uint) {
        return sdVault.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(sdVault), amount);
        sdVault.deposit(amount, address(this));
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            sdVault.withdraw(amount, address(this), address(this));
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        if (sdVaultRewards.length > 0) {
            sdVault.claim(sdVaultRewards, address(this));
        }
        try accountant.claim(harvestGauges, harvestData) {}
        catch { /* no rewards to claim */ }
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != address(sdVault), "!sdVault");
    }

    function syncVaultRewards() external onlyManager {
        sdVaultRewards = sdVault.getRewardTokens();
    }

    function setVaultRewards(address[] calldata rewards) external onlyManager {
        sdVaultRewards = rewards;
    }

}
