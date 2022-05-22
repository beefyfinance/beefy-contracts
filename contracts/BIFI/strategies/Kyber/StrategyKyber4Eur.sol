// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/kyber/IDMMRouter.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/kyber/IElysianFields.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyKyber4Eur is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public euro;
    address public stable;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public quickRouter = address(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // Routes
    IERC20[] public euroToStableRoute;
    address[] public stableToNativeRoute;
    IERC20[] public outputToWantRoute;
    address[] public euroToStablePoolsPath;
    address[] public outputToWantPoolsPath;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _euroToStableRoute,
        address[] memory _stableToNativeRoute,
        address[] memory _outputToWantRoute,
        address[] memory _euroToStablePoolsPath,
        address[] memory _outputToWantPoolsPath
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        poolId = _poolId;
        chef = _chef;

        euro = _euroToStableRoute[0];
        stable = _stableToNativeRoute[0];
        native = _stableToNativeRoute[_stableToNativeRoute.length - 1];
        output = _outputToWantRoute[0];

        stableToNativeRoute = _stableToNativeRoute;

        require(_euroToStableRoute[_euroToStableRoute.length - 1] == stable, "euroToStableRoute[last] != stable");
        for (uint i = 0; i < _euroToStableRoute.length; i++) {
            euroToStableRoute.push(IERC20(_euroToStableRoute[i]));
        }

        require(_outputToWantRoute[_outputToWantRoute.length - 1] == want, "outputToWantRoute[last] != want");
        for (uint i = 0; i < _outputToWantRoute.length; i++) {
            outputToWantRoute.push(IERC20(_outputToWantRoute[i]));
        }

        euroToStablePoolsPath = _euroToStablePoolsPath;
        outputToWantPoolsPath = _outputToWantPoolsPath;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IElysianFields(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IElysianFields(chef).withdraw(poolId, _amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            wantBal = wantBal.sub(withdrawalFeeAmount);
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IElysianFields(chef).deposit(poolId, 0);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            swapRewards();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    // no direct route from output to native, so swap output to want, withdraw euro, swap to stable, swap to native
    function chargeFees(address callFeeRecipient) internal {
        uint256 wantReserve = balanceOfWant();
        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IDMMRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToWantPoolsPath, outputToWantRoute, address(this), now);

        uint256 wantBal = balanceOfWant().sub(wantReserve);
        ICurveSwap(want).remove_liquidity_one_coin(wantBal, 0, 1);

        uint256 euroBal = IERC20(euro).balanceOf(address(this));
        IDMMRouter(unirouter).swapExactTokensForTokens(euroBal, 0, euroToStablePoolsPath, euroToStableRoute, address(this), now);

        uint256 stableBal = IERC20(stable).balanceOf(address(this));
        IUniswapRouterETH(quickRouter).swapExactTokensForTokens(stableBal, 0, stableToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function swapRewards() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IDMMRouter(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantPoolsPath, outputToWantRoute, address(this), now);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,) = IElysianFields(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IElysianFields(chef).pendingRwd(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            uint256[] memory amountOutFromOutput = IDMMRouter(unirouter).getAmountsOut(outputBal, outputToWantPoolsPath, outputToWantRoute);
            uint256 wantOut = amountOutFromOutput[amountOutFromOutput.length -1];
            uint256 euroBal = ICurveSwap(want).calc_withdraw_one_coin(wantOut, 0);
            uint256[] memory amountOutFromEuro = IDMMRouter(unirouter).getAmountsOut(euroBal, euroToStablePoolsPath, euroToStableRoute);
            uint256 stableBal = amountOutFromEuro[amountOutFromEuro.length -1];
            uint256[] memory amountOutFromStable = IUniswapRouterETH(quickRouter).getAmountsOut(stableBal, stableToNativeRoute);
            nativeOut = amountOutFromStable[amountOutFromStable.length -1];
        }

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IElysianFields(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IElysianFields(chef).emergencyWithdraw(poolId);
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(euro).safeApprove(unirouter, uint256(-1));
        IERC20(stable).safeApprove(quickRouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(euro).safeApprove(unirouter, 0);
        IERC20(stable).safeApprove(quickRouter, 0);
    }

    function euroToStable() external view returns (IERC20[] memory) {
        return euroToStableRoute;
    }

    function stableToNative() external view returns (address[] memory) {
        return stableToNativeRoute;
    }

    function outputToWant() external view returns (IERC20[] memory) {
        return outputToWantRoute;
    }

    function euroToStablePools() external view returns (address[] memory) {
        return euroToStablePoolsPath;
    }

    function outputToWantPools() external view returns (address[] memory) {
        return outputToWantPoolsPath;
    }
}