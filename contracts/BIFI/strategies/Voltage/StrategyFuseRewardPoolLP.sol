// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMultiRewards.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/StringUtils.sol";

contract StrategyFuseRewardPoolLP is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public rewardPool;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;
    address[][] public rewardToOutputRoute;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // View
    string[] public outputToLp0SymbolRoute;
    string[] public outputToLp1SymbolRoute;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _want,
        address _rewardPool,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        rewardPool = _rewardPool;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;
        
        // setup lp routing
        lpToken0 = IUniswapV2Pair(want).token0();
        require(_outputToLp0Route[0] == output, "outputToLp0Route[0] != output");
        require(_outputToLp0Route[_outputToLp0Route.length - 1] == lpToken0, "outputToLp0Route[last] != lpToken0");
        outputToLp0Route = _outputToLp0Route;

        lpToken1 = IUniswapV2Pair(want).token1();
        require(_outputToLp1Route[0] == output, "outputToLp1Route[0] != output");
        require(_outputToLp1Route[_outputToLp1Route.length - 1] == lpToken1, "outputToLp1Route[last] != lpToken1");
        outputToLp1Route = _outputToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IMultiRewards(rewardPool).stake(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IMultiRewards(rewardPool).withdraw(_amount.sub(wantBal));
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, wantBal);
        } else {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFeeAmount));
        }

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

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IMultiRewards(rewardPool).getReward();
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
    function chargeFees(address callFeeRecipient) internal {
        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                uint256 rewardBal = IERC20(rewardToOutputRoute[i][0]).balanceOf(address(this));
                if (rewardBal > 0) {
                    IUniswapRouterETH(unirouter).swapExactTokensForTokens(rewardBal, 0, rewardToOutputRoute[i], address(this), now);
                }
            }
        }

        uint256 nativeBal = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        if (output != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeBal, 0, outputToNativeRoute, address(this), now);
            nativeBal = IERC20(native).balanceOf(address(this));
        }

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputHalf = IERC20(output).balanceOf(address(this)).div(2);

        if (lpToken0 != output) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputHalf, 0, outputToLp0Route, address(this), now);
        }

        if (lpToken1 != output) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputHalf, 0, outputToLp1Route, address(this), now);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouterETH(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), now);
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
        return IMultiRewards(rewardPool).balanceOf(address(this));
    }

     // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256 nativeBal) {
       nativeBal = IMultiRewards(rewardPool).earned(address(this), native);

       if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                try IMultiRewards(rewardPool).earned(address(this), rewardToOutputRoute[i][0])
                returns(uint256 initialAmountOut) {
                    uint256 outputBal = initialAmountOut;
                    uint256[] memory finalAmountOut = IUniswapRouterETH(unirouter).getAmountsOut(outputBal, rewardToOutputRoute[i]);
                    nativeBal += finalAmountOut[finalAmountOut.length - 1];
                } catch {}
            }
        }
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 nativeOut = rewardsAvailable();

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMultiRewards(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
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

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(rewardPool, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, uint256(-1));

        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                IERC20(rewardToOutputRoute[i][0]).safeApprove(unirouter, 0);
                IERC20(rewardToOutputRoute[i][0]).safeApprove(unirouter, uint256(-1));
            }
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);

        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                IERC20(rewardToOutputRoute[i][0]).safeApprove(unirouter, 0);
            }
        }
    }

    function addRewardRoute(address[] memory _rewardToOutputRoute) external onlyOwner {
        require(_rewardToOutputRoute[_rewardToOutputRoute.length -1] == output, '!output');
        IERC20(_rewardToOutputRoute[0]).safeApprove(unirouter, 0);
        IERC20(_rewardToOutputRoute[0]).safeApprove(unirouter, uint256(-1));
        rewardToOutputRoute.push(_rewardToOutputRoute);
    }

    function removeLastRewardRoute() external onlyManager {
        address reward = rewardToOutputRoute[rewardToOutputRoute.length - 1][0];
        if (reward != lpToken0 && reward != lpToken1) {
            IERC20(reward).safeApprove(unirouter, 0);
        }
        rewardToOutputRoute.pop();
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToLp0() external view returns (address[] memory) {
        return outputToLp0Route;
    }

    function outputToLp1() external view returns (address[] memory) {
        return outputToLp1Route;
    }

    function rewardToOutput() external view returns (address[][] memory) {
        return rewardToOutputRoute;
    }
}
