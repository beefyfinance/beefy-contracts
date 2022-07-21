// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IStableRouter.sol";
import "../../interfaces/tri/ITriChef.sol";
import "../../interfaces/tri/ITriRewarder.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/StringUtils.sol";
import "../../utils/GasThrottler.sol";

contract StrategyTriMiniChefDualStable is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public reward;
    address public want;
    address public input;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public stableRouter;
    uint256 public depositIndex;

    uint256 public lastHarvest;
    uint256 public liquidityBal;
    bool public feesCharged = false;
    bool public harvestAndSwapped = false;
    bool public swapped = false;
    bool public liquidityAdded = false;
    bool public harvested = false;

    // Routes
    address[] public outputToNativeRoute;
    address[] public rewardToOutputRoute;
    address[] public outputToInputRoute;

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
        address _stableRouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _rewardToOutputRoute,
        address[] memory _outputToInputRoute
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        poolId = _poolId;
        chef = _chef;
        stableRouter = _stableRouter;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        // setup lp routing
        require(_rewardToOutputRoute[_rewardToOutputRoute.length - 1] == output, "rewardToOutputRoute[last] != output");
        reward = _rewardToOutputRoute[0];
        rewardToOutputRoute = _rewardToOutputRoute;

        require(_outputToInputRoute[0] == output, "outputToInputRoute[0] != output");
        input = _outputToInputRoute[_outputToInputRoute.length - 1];
        outputToInputRoute = _outputToInputRoute;

        _giveAllowances();
    }

    // Grabs deposits from vault
    function deposit() public whenNotPaused {} 

    // Puts the funds to work
    function sweep() public whenNotPaused {
        if (balanceOfWant() > 0) {
            ITriChef(chef).deposit(poolId, balanceOfWant(), address(this));
            emit Deposit(balanceOfWant());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ITriChef(chef).withdraw(poolId, _amount.sub(wantBal), address(this));
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
            if (swapped){
                if (liquidityAdded) {
                    ITriChef(chef).deposit(poolId, balanceOfWant(), address(this));
                    toggleHarvest();
                    lastHarvest = block.timestamp;
                    emit StratHarvest(msg.sender, balanceOfWant(), balanceOf());
                } else {
                    addLiquidity();
                }
            } else {
                swap();
            }
        } else {
            if (harvestAndSwapped) {
                uint256 outputBal = IERC20(output).balanceOf(address(this));
                if (outputBal > 0) {
                    chargeFees(callFeeRecipient);
                }
            } else {
                if (harvested) {
                    uint256 rewardBal = IERC20(reward).balanceOf(address(this));
                    if (rewardBal > 0 && canTrade(rewardBal, rewardToOutputRoute)) {
                        IUniswapRouterETH(unirouter).swapExactTokensForTokens(rewardBal, 0, rewardToOutputRoute, address(this), now);
                    }
                    harvestAndSwapped = true;
                } else {
                    ITriChef(chef).harvest(poolId, address(this));
                    harvested = true;
                }
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
        bool tradeInput = input != output ? canTrade(liquidityBal, outputToInputRoute): true;
        require(tradeInput == true, "Not enough output");
        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFee);
    }

    function swap() internal  {
        if (input != output) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(liquidityBal, 0, outputToInputRoute, address(this), now);
        }
        swapped = true;
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256[] memory inputs = new uint256[](3);
        inputs[depositIndex] = IERC20(input).balanceOf(address(this));
        IStableRouter(stableRouter).addLiquidity(inputs, 1, now);
        liquidityBal = 0;
        liquidityAdded = true;
    }

    // Toggle harvest cycle to false to start again 
    function toggleHarvest() internal {
        feesCharged = false;
        swapped = false;
        harvestAndSwapped = false;
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
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,) = ITriChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        uint256 first = ITriChef(chef).pendingTri(poolId, address(this));
        uint256 second;
        address rewarder = ITriChef(chef).rewarder(poolId);
        if (rewarder != address(0)) {
            uint256[] memory rewards = new uint256[](1);
            (, rewards) = ITriRewarder(rewarder).pendingTokens(poolId, address(this), 0);

            try IUniswapRouterETH(unirouter).getAmountsOut(rewards[0], rewardToOutputRoute)
            returns (uint256[] memory amountOut)
        {
            second = amountOut[amountOut.length -1];
        }
            catch {} 
        }
        return first.add(second);
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

        ITriChef(chef).emergencyWithdraw(poolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ITriChef(chef).emergencyWithdraw(poolId, address(this));
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
        IERC20(want).safeApprove(chef, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(reward).safeApprove(unirouter, uint256(-1));

        IERC20(input).safeApprove(stableRouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(reward).safeApprove(unirouter, 0);
        IERC20(input).safeApprove(stableRouter, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToInput() external view returns (address[] memory) {
        return outputToInputRoute;
    }

    function rewardToOutput() external view returns (address[] memory) {
        return rewardToOutputRoute;
    }
}
