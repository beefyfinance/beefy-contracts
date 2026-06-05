// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin-5/contracts/interfaces/IERC4626.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

contract StrategyMorpho is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IERC4626 public morphoVault;
    IMerklClaimer public claimer;
    uint public storedBalance;

    function initialize(
        address _morphoVault,
        address _claimer,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);
        morphoVault = IERC4626(_morphoVault);
        claimer = IMerklClaimer(_claimer);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "Morpho";
    }

    function balanceOfPool() public view override returns (uint) {
        return storedBalance;
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(morphoVault), amount);
        // round down to the nearest amount of shares to mint for deposited assets
        uint256 shares = morphoVault.previewDeposit(amount);
        // mint the shares, leaving a small amount of dust in the strategy
        morphoVault.mint(shares, address(this));
        // update the stored balance to the amount of assets that can be redeemed from the newly minted shares, rounded down
        storedBalance += morphoVault.previewRedeem(shares);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            // round up to the nearest amount of shares to withdraw for the requested amount
            uint256 requiredShares = morphoVault.previewWithdraw(amount);
            // redeem the shares, leaving a small amount of dust in the strategy
            uint256 redeemedAmount = morphoVault.redeem(requiredShares, address(this), address(this));
            storedBalance -= redeemedAmount;
        }
    }

    function _emergencyWithdraw() internal override {
        storedBalance = 0;
        uint bal = morphoVault.balanceOf(address(this));
        if (bal > 0) {
            morphoVault.redeem(bal, address(this), address(this));
        }
    }

    function _claim() internal override {}

    function _swapRewardsToNative() internal override {
        // round up to the nearest amount of shares needed to withdraw the stored balance
        uint256 requiredShares = morphoVault.previewWithdraw(storedBalance);
        // find the amount of shares currently in the vault
        uint256 shares = morphoVault.balanceOf(address(this));
        // if the share balance is greater than the required shares, redeem the difference
        if (shares > requiredShares) {
            uint256 sharesToRedeem = shares - requiredShares;
            uint256 redeemedAmount = morphoVault.previewRedeem(sharesToRedeem);
            if (redeemedAmount > minAmounts[want]) {
                redeemedAmount = morphoVault.redeem(sharesToRedeem, address(this), address(this));
                _swap(want, native, redeemedAmount);
            }
        }
        super._swapRewardsToNative();
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != address(morphoVault), "!morphoVault");
    }

    // Morpho vaults can have `want` as reward, timelocked
    function addWantAsReward() external onlyOwner {
        rewards.push(want);
    }

    /// @notice Claim rewards from the underlying platform
    function claim(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    ) external {
        address[] memory users = new address[](1);
        users[0] = address(this);

        claimer.claim(users, _tokens, _amounts, _proofs);
    }

    function setClaimer(address _claimer) external onlyManager {
        claimer = IMerklClaimer(_claimer);
    }

    function setStoredBalance() external onlyOwner {
        uint bal = morphoVault.balanceOf(address(this));
        storedBalance = morphoVault.previewRedeem(bal);
    }
}