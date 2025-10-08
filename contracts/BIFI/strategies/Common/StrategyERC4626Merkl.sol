// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin-4/contracts/interfaces/IERC4626.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

contract StrategyERC4626Merkl is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IERC4626 public erc4626Vault;
    IMerklClaimer public claimer;

    function initialize(
        address _erc4626Vault,
        address _claimer,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);
        erc4626Vault = IERC4626(_erc4626Vault);
        claimer = IMerklClaimer(_claimer);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "ERC4626Merkl";
    }

    function balanceOfPool() public view override returns (uint) {
        return erc4626Vault.convertToAssets(erc4626Vault.balanceOf(address(this)));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(erc4626Vault), amount);
        erc4626Vault.deposit(amount, address(this));
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            erc4626Vault.withdraw(amount, address(this), address(this));
        }
    }

    function _emergencyWithdraw() internal override {
        uint bal = erc4626Vault.balanceOf(address(this));
        if (bal > 0) {
            erc4626Vault.redeem(bal, address(this), address(this));
        }
    }

    function _claim() internal override {}

    function _verifyRewardToken(address token) internal view override {
        require(token != address(erc4626Vault), "!erc4626Vault");
    }

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
}
