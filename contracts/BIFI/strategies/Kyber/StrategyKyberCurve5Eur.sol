// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/kyber/IDMMRouter.sol";
import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/kyber/IElysianFields.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyKyberCurve5Eur is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public stable;
    address public depositToken;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public quickRouter;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // Routes
    address[] public stableToDepositRoute;
    IERC20[] public outputToNativeRoute;
    IERC20[] public outputToStableRoute;
    address[] public outputToNativePoolsPath;
    address[] public outputToStablePoolsPath;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _vault,
        address _unirouter,
        address _quickRouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToStableRoute,
        address[] memory _stableToDepositRoute,
        address[] memory _outputToNativePoolsPath,
        address[] memory _outputToStablePoolsPath
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        poolId = _poolId;
        chef = _chef;
        quickRouter = _quickRouter;

        stable = _stableToDepositRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        output = _outputToNativeRoute[0];
        depositToken = _stableToDepositRoute[_stableToDepositRoute.length - 1];

        for (uint i = 0; i < _outputToNativeRoute.length; i++) {
            outputToNativeRoute.push(IERC20(_outputToNativeRoute[i]));
        }

        // setup lp routing
        for (uint i = 0; i < _outputToStableRoute.length; i++) {
            outputToStableRoute.push(IERC20(_outputToStableRoute[i]));
        }

        stableToDepositRoute = _stableToDepositRoute;
        outputToNativePoolsPath = _outputToNativePoolsPath;
        outputToStablePoolsPath = _outputToStablePoolsPath;

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
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    // no direct route from output to native, so swap output to want then withdraw stable and swap to native
    function chargeFees(address callFeeRecipient) internal {
        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IDMMRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativePoolsPath, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IDMMRouter(unirouter).swapExactTokensForTokens(outputBal, 0, outputToStablePoolsPath, outputToStableRoute, address(this), now);

        uint256 toDeposit = IERC20(stable).balanceOf(address(this));
        IUniswapRouter(quickRouter).swapExactTokensForTokens(toDeposit, 0, stableToDepositRoute, address(this), now);

        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));

        uint256[2] memory amounts;
        amounts[0] = depositBal;
        ICurveSwap(want).add_liquidity(amounts, 0);
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
            try IDMMRouter(unirouter).getAmountsOut(outputBal, outputToNativePoolsPath, outputToNativeRoute)
                returns (uint256[] memory amountOutFromOutput)
            {
                nativeOut = amountOutFromOutput[amountOutFromOutput.length -1];
            }
            catch {}
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
        IERC20(stable).safeApprove(quickRouter, uint256(-1));
        IERC20(depositToken).safeApprove(want, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(stable).safeApprove(quickRouter, 0);
        IERC20(depositToken).safeApprove(want, 0);
    }

    function outputToNative() external view returns (IERC20[] memory) {
        return outputToNativeRoute;
    }

    function outputToStable() external view returns (IERC20[] memory) {
        return outputToStableRoute;
    }

    function stableToDeposit() external view returns (address[] memory) {
        return stableToDepositRoute;
    }

    function outputToNativePools() external view returns (address[] memory) {
        return outputToNativePoolsPath;
    }

    function outputToStablePools() external view returns (address[] memory) {
        return outputToStablePoolsPath;
    }
}