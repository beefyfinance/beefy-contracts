// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/GasThrottler.sol";

contract StrategyBifiMaxiLowGas is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public output;
    address public want;

    // Third party contracts
    address public rewardPool;

    // Routes
    address[] public outputToWantRoute;

    uint256 public lastHarvest;
    uint256 public wantHarvested;
    bool public feesCharged;
    bool public swapped;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        address _rewardPool,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToWantRoute
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        rewardPool = _rewardPool;
        
        require(_outputToWantRoute[_outputToWantRoute.length - 1] == want, "outputToWantRoute[last] != want");
        outputToWantRoute = _outputToWantRoute;
        output = _outputToWantRoute[0];

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IRewardPool(rewardPool).stake(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IRewardPool(rewardPool).withdraw(_amount.sub(wantBal));
            wantBal = balanceOfWant();
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
                uint256 wantBal = balanceOfWant();
                if (wantBal > 0) {
                    IRewardPool(rewardPool).stake(wantBal);
                }
                feesCharged = false;
                swapped = false;
                lastHarvest = block.timestamp;
                emit StratHarvest(msg.sender, wantHarvested, balanceOf());
            } else {
                swapRewards();
            }
        } else {
            IRewardPool(rewardPool).getReward();
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            if (outputBal > 0) {
                chargeFees(callFeeRecipient);
            }
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 callFeeAmount = IERC20(output).balanceOf(address(this)).mul(45).div(1000).mul(callFee).div(MAX_FEE);
        IERC20(output).safeTransfer(callFeeRecipient, callFeeAmount);
        feesCharged = true;
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        require(canTrade(outputBal, outputToWantRoute), 'Not enough output');
        emit ChargedFees(callFeeAmount, 0, 0);
    }

    // swaps rewards to 'want'
    function swapRewards() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantRoute, address(this), now);
        swapped = true;
        wantHarvested = balanceOfWant();
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
        return IRewardPool(rewardPool).balanceOf(address(this));
    }

    // validates if we can trade because of decimals
    function canTrade(uint256 inputAmount, address[] memory route) internal view returns (bool tradeable) {
        uint256[] memory amountsOut = IUniswapRouterETH(unirouter).getAmountsOut(inputAmount, route);
        tradeable = amountsOut[amountsOut.length -1] > 0;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IRewardPool(rewardPool).earned(address(this));
    }

    // native reward amount for calling harvest
    function callReward() external view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        return outputBal.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardPool(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IRewardPool(rewardPool).withdraw(balanceOfPool());
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
        IERC20(want).safeApprove(rewardPool, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function outputToWant() external view returns (address[] memory) {
        return outputToWantRoute;
    }
}
