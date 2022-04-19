// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMultiRewards.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/StringUtils.sol";
import "../../utils/GasThrottler.sol";

contract StrategyRoseLP is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public stable;
    address public want;

    // Third party contracts
    address public rewardPool;
    address public metaRouter;
    address public lp;
    address public roseRouter;

    uint256 public lastHarvest;
    uint256 public liquidityBal;
    bool public feesCharged = false;
    bool public createdLp = false;
    bool public swapped = false;
    bool public liquidityAdded = false;
    bool public harvested = false;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToStableRoute;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        address _rewardPool,
        address _metaRouter,
        address _roseRouter,
        address _lp,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToStableRoute
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        rewardPool = _rewardPool;
        metaRouter = _metaRouter;
        roseRouter = _roseRouter;
        lp = _lp;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        stable = _outputToStableRoute[_outputToStableRoute.length - 1];
        outputToStableRoute = _outputToStableRoute;
      
        _giveAllowances();
    }

    // Grabs deposits from vault
    function deposit() public whenNotPaused {} 

    // Puts the funds to work
    function sweep() public whenNotPaused {
        if (balanceOfWant() > 0) {
                IMultiRewards(rewardPool).stake(balanceOfWant());
                emit Deposit(balanceOfWant());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMultiRewards(rewardPool).withdraw(_amount.sub(wantBal));
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

    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external gasThrottle virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
            if (feesCharged) {
                if (swapped) {
                    if (liquidityAdded) {
                        IMultiRewards(rewardPool).stake(balanceOfWant());
                        toggleHarvest();
                        lastHarvest = block.timestamp;
                        emit StratHarvest(msg.sender, balanceOfWant(), balanceOf());
                    } else {
                        if (createdLp) {
                            addLiquidity();
                        } else {
                            createLP();
                        }
                    }
                } else {
                    swap();
                }
            } else {
                if (harvested) {
                    uint256 outputBal = IERC20(output).balanceOf(address(this));
                    if (outputBal > 0) {
                        chargeFees(callFeeRecipient);
                    }
                } else {
                    IMultiRewards(rewardPool).getReward();
                    harvested = true;
                }
            }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
        feesCharged = true;
        liquidityBal = IERC20(output).balanceOf(address(this));
        bool trade = canTrade(liquidityBal, outputToStableRoute);
        require(trade == true, "Not enough output");
        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFee);
    }

    function swap() internal  {
        uint256 outputRemaining = liquidityBal;
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputRemaining, 0, outputToStableRoute, address(this), now);
        
        liquidityBal = 0;
        swapped = true;
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 lpBal = IERC20(lp).balanceOf(address(this));
        uint256[2] memory amounts;
        amounts[1] = lpBal;
        ICurveSwap2(metaRouter).add_liquidity(amounts, 0);
        
        liquidityAdded = true;
    }

     // Adds liquidity to AMM and gets more LP tokens.
    function createLP() internal {
        uint256 stableBal = IERC20(stable).balanceOf(address(this));
        uint256[3] memory amounts;
        amounts[1] = stableBal;
        ICurveSwap3(roseRouter).add_liquidity(amounts, 0);
        
        createdLp = true;
    }

    // Toggle harvest cycle to false to start again 
    function toggleHarvest() internal {
        feesCharged = false;
        swapped = false;
        createdLp = false;
        liquidityAdded = false;
        harvested = false;
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
    function balanceOfPool() public view returns (uint256 _amount) {
         _amount = IMultiRewards(rewardPool).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IMultiRewards(rewardPool).earned(address(this), output);
    }

    // Validates if we can trade because of decimals
    function canTrade(uint256 tradeableOutput, address[] memory route) internal view returns (bool tradeable) {
        try IUniswapRouterETH(unirouter).getAmountsOut(tradeableOutput, route)
            returns (uint256[] memory amountOut) 
            {
                uint256 amount = amountOut[amountOut.length -1];
                if (amount > 0) {
                    tradeable = true;
                }
            }
            catch { 
                tradeable = false; 
            }
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeBal;

        try IUniswapRouterETH(unirouter).getAmountsOut(outputBal, outputToNativeRoute)
            returns (uint256[] memory amountOut)
        {
            nativeBal = nativeBal.add(amountOut[amountOut.length -1]);
        }
        catch {}

        return nativeBal.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMultiRewards(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMultiRewards(rewardPool).withdraw(balanceOfPool());
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        sweep();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(rewardPool, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(stable).safeApprove(roseRouter, uint256(-1));
        IERC20(lp).safeApprove(metaRouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(stable).safeApprove(roseRouter, 0);
        IERC20(lp).safeApprove(metaRouter, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToStable() external view returns (address[] memory) {
        return outputToStableRoute;
    }
}
