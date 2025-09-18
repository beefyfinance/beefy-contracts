// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {BaseAllToNativeFactoryStrat} from "../Common/BaseAllToNativeFactoryStrat.sol";
import {IBeefySwapper} from "../../interfaces/beefy/IBeefySwapper.sol";
import {IERC20, SafeERC20} from "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISiloV2} from "../../interfaces/silo/ISiloV2.sol";
import {IIncentivesGauge} from "../../interfaces/silo/IIncentivesGauge.sol";
import {IMerklClaimer} from "../../interfaces/merkl/IMerklClaimer.sol";

/**
 * @title Strategy Silo Vault Factory
 * @author Weso, Beefy
 * @notice Sells rewards and compounds them back into the SiloV2 4626 position.
 */
contract StrategySiloVault is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    // Tokens used
    ISiloV2 public silo;
    IIncentivesGauge public gauge; 
    IMerklClaimer public claimer;

    function initialize(
        address _silo,
        address _gauge,
        address[] calldata _rewards,
        Addresses calldata _commonAddresses
    ) public initializer {
        silo = ISiloV2(_silo);
        gauge = IIncentivesGauge(_gauge);
 
        __BaseStrategy_init(_commonAddresses, _rewards);
        _giveAllowances();

        setMerklClaimer(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae);
    }

    function balanceOfPool() public view override returns (uint) {
        uint256 shares = silo.balanceOf(address(this));
        return silo.convertToAssets(shares);
    }

    function stratName() public pure override returns (string memory) {
        return "SiloVault";
    }

    function _deposit(uint _amount) internal override {
        silo.deposit(_amount, address(this));
    }

    function _withdraw(uint _amount) internal override {
        if (_amount > 0) {
            if (_amount == balanceOfPool()) silo.redeem(silo.balanceOf(address(this)), address(this), address(this));
            else silo.withdraw(_amount, address(this), address(this));
        }
    }

    function _emergencyWithdraw() internal override {
        uint256 shares = silo.balanceOf(address(this));
        silo.redeem(shares, address(this), address(this));
    }

    function _claim() internal override {
        if (address(gauge) != address(0)) gauge.claimRewards(address(this));
    }

    function _swapNativeToWant() internal override {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        if (want != native) {
            IBeefySwapper(swapper).swap(native, want, nativeBal);
        }
    }

    function _giveAllowances() internal {
        uint max = type(uint).max;
        _approve(want, address(silo), max);
        _approve(native, address(swapper), max);
    }

    function _removeAllowances() internal {
        _approve(want, address(silo), 0);
        _approve(native, address(swapper), 0);
    }

    function setMerklClaimer(address _claimer) public onlyManager {
        claimer = IMerklClaimer(_claimer);
    }

    function setGauge(address _gauge) external onlyManager {
        gauge = IIncentivesGauge(_gauge);
    }

    function panic() public override onlyManager {
        pause();
        _emergencyWithdraw();
        _removeAllowances();
    }

    function pause() public override onlyManager {
        _pause();
        _removeAllowances();
    }

    function unpause() external override onlyManager {
        _unpause();
        _giveAllowances();
        deposit();
    }


    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).approve(_spender, amount);
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

    function _verifyRewardToken(address token) internal view override {}
}
