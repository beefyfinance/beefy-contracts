// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IStrategyMorphoMerklFeeOnLend } from "../Interfaces/IStrategyMorphoMerklFeeOnLend.sol";
import { StrategyMorphoMerklFeeOnLendStorageUtils } from "../Storage/StrategyMorphoMerklFeeOnLendStorage.sol";
import { BaseAllToNativeFactoryStratNew } from "../Common/BaseAllToNativeFactoryStratNew.sol";
import { IERC4626 } from "@openzeppelin-4/contracts/interfaces/IERC4626.sol";
import { IMerklClaimer } from "../../../interfaces/merkl/IMerklClaimer.sol";
import { SafeERC20, IERC20 } from "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";

// @title StrategyMorphoMerklFeeOnLend
// @author Beefy
// @notice Strategy for Morpho vaults with fee on lend
contract StrategyMorphoMerklFeeOnLend is BaseAllToNativeFactoryStratNew, IStrategyMorphoMerklFeeOnLend, StrategyMorphoMerklFeeOnLendStorageUtils {
    using SafeERC20 for IERC20;

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function initialize(
        address _morphoVault,
        address _claimer,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        __BaseStrategy_init(_addresses, _rewards);
        $.morphoVault = _morphoVault;
        $.claimer = _claimer;
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function stratName() public pure override returns (string memory) {
        return "MorphoMerkl";
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function balanceOfPool() public view override returns (uint) {
        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        return IERC4626($.morphoVault).convertToAssets(IERC20($.morphoVault).balanceOf(address(this)));
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function _deposit(uint amount) internal override {
        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        IERC20(want()).forceApprove(address($.morphoVault), amount);
        IERC4626($.morphoVault).deposit(amount, address(this));
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function _withdraw(uint amount) internal override {
        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        if (amount > 0) {
            IERC4626($.morphoVault).withdraw(amount, address(this), address(this));
        }
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function _emergencyWithdraw() internal override {
        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        uint bal = IERC20($.morphoVault).balanceOf(address(this));
        if (bal > 0) {
            IERC4626($.morphoVault).redeem(bal, address(this), address(this));
        }
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function _claim() internal override {}

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function _verifyRewardToken(address _token) internal view override {
        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        require(_token != address($.morphoVault), "!morphoVault");
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function addWantAsReward() external onlyOwner {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        $.rewards.push(want());
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function claim(
        address[] calldata _tokens,
        uint256[] calldata _amounts,
        bytes32[][] calldata _proofs
    ) external { 
        address[] memory users = new address[](1);
        users[0] = address(this);

        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        IMerklClaimer($.claimer).claim(users, _tokens, _amounts, _proofs);
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function morphoVault() public view returns (address) {
        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        return $.morphoVault;
    }

    // @inheritdoc IStrategyMorphoMerklFeeOnLend
    function claimer() public view returns (address) {
        StrategyMorphoMerklFeeOnLendStorage storage $ = getStrategyMorphoMerklFeeOnLendStorage();
        return $.claimer;
    }
}