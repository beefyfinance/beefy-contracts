// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IERC20Extended.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IStakingDualRewards.sol";
import "../../interfaces/quick/IDragonsLair.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyQuickswapDualRewardLP is StratManager, FeeManager {
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
    address constant public dragonsLair = address(0xf28164A485B0B2C90639E47b0f377b4a438a16B1);

    // Routes
    address[] public outputToNativeRoute;
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

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
        address[] memory _nativeToLp0Route,
        address[] memory _nativeToLp1Route
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        rewardPool = _rewardPool;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        // setup lp routing
        lpToken0 = IUniswapV2Pair(want).token0();
        require(_nativeToLp0Route[0] == native, "outputToLp0Route[0] != output");
        require(_nativeToLp0Route[_nativeToLp0Route.length - 1] == lpToken0, "nativeToLp0Route[last] != lpToken0");
        nativeToLp0Route = _nativeToLp0Route;

        lpToken1 = IUniswapV2Pair(want).token1();
        require(_nativeToLp1Route[0] == output,  "nativeToLp1Route[0] != output");
        require(_nativeToLp1Route[_nativeToLp1Route.length - 1] == lpToken1, "nativeToLP1Route[last] != lpToken1");
        nativeToLp1Route = _nativeToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IStakingDualRewards(rewardPool).stake(wantBal);
        }
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IStakingDualRewards(rewardPool).withdraw(_amount.sub(wantBal));
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
        IStakingDualRewards(rewardPool).getReward();
        uint256 lairBal = IERC20(dragonsLair).balanceOf(address(this));
        IDragonsLair(dragonsLair).leave(lairBal);

        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 rewardBal = IERC20(native).balanceOf(address(this));

        if (outputBal > 0 || rewardBal > 0) {
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
        uint256 outputToNative = IERC20(output).balanceOf(address(this));
        if (outputToNative > 0) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputToNative, 0, outputToNativeRoute, address(this), block.timestamp);
        }

        uint256 nativeBal = IERC20(native).balanceOf(address(this)).mul(45).div(1000); //4.5% of total native balance

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)).div(2);

        if (lpToken0 != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp0Route, address(this), now);
        }

        if (lpToken1 != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp1Route, address(this), now);
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
        return IStakingDualRewards(rewardPool).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAAvailable() public view returns (uint256) {
        uint256 lairReward = IStakingDualRewards(rewardPool).earnedA(address(this));
        return IDragonsLair(dragonsLair).dQUICKForQUICK(lairReward);
    }

    // returns rewards unharvested
    function rewardsBAvailable() public view returns (uint256) {
       return IStakingDualRewards(rewardPool).earnedB(address(this));
    }

    // returns native reward for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAAvailable();
        uint256 nativeBal = rewardsBAvailable();

        uint256 nativeOut;
        if (outputBal > 0) {
            try IUniswapRouterETH(unirouter).getAmountsOut(outputBal, outputToNativeRoute)
            returns (uint256[] memory amountOut)
            {
                nativeOut = amountOut[amountOut.length - 1];
            }
            catch {}
        }

        nativeOut = nativeOut.add(nativeBal);

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IStakingDualRewards(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit == true) {
            super.setWithdrawalFee(0);
        } else {
            super.setWithdrawalFee(10);
        }
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IStakingDualRewards(rewardPool).withdraw(balanceOfPool());
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

    function nativeToLp0() public view returns (address[] memory) {
        return nativeToLp0Route;
    }

    function nativeToLp1() public view returns (address[] memory) {
        return nativeToLp1Route;
    }

    function outputToNative() public view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(rewardPool, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(native).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }
}
