// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin-5/contracts/interfaces/IERC4626.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

/// @title StrategyERC4626
/// @author Beefy
/// @notice A strategy for ERC4626 vaults that also supports claiming rewards from Merkl
contract StrategyERC4626 is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    /// @notice The ERC4626 vault
    IERC4626 public erc4626;
    /// @notice The Merkl claimer
    IMerklClaimer public claimer;
    /// @notice The stored balance of the strategy
    uint256 public storedBalance;

    /// @notice Initializes the strategy
    /// @param _erc4626 The address of the ERC4626 vault
    /// @param _claimer The address of the Merkl claimer
    /// @param _harvestOnDeposit Whether to harvest on deposit
    /// @param _rewards The addresses of the rewards to claim
    /// @param _addresses The addresses of the strategy
    function initialize(
        address _erc4626,
        address _claimer,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);
        erc4626 = IERC4626(_erc4626);
        claimer = IMerklClaimer(_claimer);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    /// @notice The name of the strategy
    /// @return The name of the strategy
    function stratName() public pure override returns (string memory) {
        return "ERC4626";
    }

    /// @notice The balance of the strategy in the pool
    /// @return The balance of the strategy in the pool
    function balanceOfPool() public view override returns (uint) {
        return storedBalance;
    }

    /// @dev Assets are deposited into the ERC4626 vault using the `mint` function to prevent dust from being lost.
    /// @param amount The amount of assets to deposit
    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(erc4626), amount);
        // round down to the nearest amount of shares to mint for deposited assets
        uint256 shares = erc4626.previewDeposit(amount);
        // mint the shares, leaving a small amount of dust in the strategy
        erc4626.mint(shares, address(this));
        // update the stored balance to the amount of assets that can be redeemed from the newly minted shares, rounded down
        storedBalance += erc4626.previewRedeem(shares);
    }

    /// @dev Assets are withdrawn from the ERC4626 vault using the `redeem` function to prevent dust from being lost.
    /// @param amount The amount of assets to withdraw
    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            // round up to the nearest amount of shares to withdraw for the requested amount
            uint256 requiredShares = erc4626.previewWithdraw(amount);
            // redeem the shares, leaving a small amount of dust in the strategy
            uint256 redeemedAmount = erc4626.redeem(requiredShares, address(this), address(this));
            storedBalance -= redeemedAmount;
        }
    }

    /// @dev Emergency withdraw is called when the strategy is panicked
    function _emergencyWithdraw() internal override {
        storedBalance = 0;
        uint bal = erc4626.balanceOf(address(this));
        if (bal > 0) {
            erc4626.redeem(bal, address(this), address(this));
        }
    }

    /// @dev Claims rewards from the underlying platform
    function _claim() internal override {}

    /// @dev Native yield is charged by redeeming excess shares from the ERC4626 vault
    function _swapRewardsToNative() internal override {
        // round up to the nearest amount of shares needed to withdraw the stored balance
        uint256 requiredShares = erc4626.previewWithdraw(storedBalance);
        // find the amount of shares currently in the vault
        uint256 shares = erc4626.balanceOf(address(this));
        // if the share balance is greater than the required shares, redeem the difference
        if (shares > requiredShares) {
            uint256 sharesToRedeem = shares - requiredShares;
            uint256 redeemedAmount = erc4626.redeem(sharesToRedeem, address(this), address(this));
            _swap(want, native, redeemedAmount);
        }
        super._swapRewardsToNative();
    }

    /// @dev Verifies that the reward token is not the ERC4626 vault
    /// @param token The address of the reward token
    function _verifyRewardToken(address token) internal view override {
        require(token != address(erc4626), "!erc4626");
    }

    /// @notice Adds `want` as a reward token
    /// @dev ERC4626 vaults can have `want` as reward, but any dust left in the strategy will be charged as a reward
    function addWantAsReward() external onlyOwner {
        rewards.push(want);
    }

    /// @notice Claim rewards from the underlying platform
    /// @param _tokens The addresses of the tokens to claim
    /// @param _amounts The amounts of the tokens to claim
    /// @param _proofs The proofs of the tokens to claim
    function claim(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    ) external {
        address[] memory users = new address[](_tokens.length);
        for (uint256 i; i < _tokens.length; ++i) {
            users[i] = address(this);
        }
        claimer.claim(users, _tokens, _amounts, _proofs);
    }

    /// @notice Sets the Merkl claimer
    /// @param _claimer The address of the Merkl claimer
    function setClaimer(address _claimer) external onlyManager {
        claimer = IMerklClaimer(_claimer);
    }
}