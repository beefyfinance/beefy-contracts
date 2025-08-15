// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin-5/contracts/interfaces/IERC4626.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

contract StrategyMorpho is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IERC4626 public morphoVault;
    IMerklClaimer public claimer;

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
}