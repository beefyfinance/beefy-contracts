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

contract StrategyTelxchangeDualRewardLP is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public want;

    address public rewardA; // Tel
    address public rewardB; // dQuick

    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public rewardPool;
    address constant public dragonsLair = address(0xf28164A485B0B2C90639E47b0f377b4a438a16B1);

    // Routes
    address[] public rewardAToNativeRoute;
    address[] public rewardBToRewardARoute;
    
    address[] public rewardAToLp0Route;
    address[] public rewardAToLp1Route;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;


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
        address[] memory _rewardAToNativeRoute,
        address[] memory _rewardBToRewardARoute,
        address[] memory _rewardAToLp0Route,
        address[] memory _rewardAToLp1Route
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        rewardPool = _rewardPool;

        rewardA = _rewardAToNativeRoute[0];
        native = _rewardAToNativeRoute[_rewardAToNativeRoute.length - 1];
        rewardAToNativeRoute = _rewardAToNativeRoute;

        rewardB = _rewardBToRewardARoute[0];
        require(_rewardBToRewardARoute[_rewardBToRewardARoute.length - 1] == rewardA, "_rewardBToRewardARoute[_rewardBToRewardARoute.length - 1] == rewardA");
        rewardBToRewardARoute = _rewardBToRewardARoute;

        // setup lp routing
        lpToken0 = IUniswapV2Pair(want).token0();
        require(_rewardAToLp0Route[0] == rewardA, "rewardAToLp0Route[0] != rewardA");
        require(_rewardAToLp0Route[_rewardAToLp0Route.length - 1] == lpToken0, "rewardAToLp0Route[last] != lpToken0");
        rewardAToLp0Route = _rewardAToLp0Route;

        lpToken1 = IUniswapV2Pair(want).token1();
        require(_rewardAToLp1Route[0] == rewardA,  "rewardAToLp1Route[0] != rewardA");
        require(_rewardAToLp1Route[_rewardAToLp1Route.length - 1] == lpToken1, "nativeToLP1Route[last] != lpToken1");
        rewardAToLp1Route = _rewardAToLp1Route;

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

        uint256 rewardABal = IERC20(rewardA).balanceOf(address(this));
        uint256 rewardBBal = IERC20(rewardB).balanceOf(address(this));

        if (rewardABal > 0 || rewardBBal > 0) {
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
        uint256 rewardBToRewardA = IERC20(rewardB).balanceOf(address(this));
        if (rewardBToRewardA > 0) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(rewardBToRewardA, 0, rewardBToRewardARoute, address(this), block.timestamp);
        }

        uint256 rewardAToNative = IERC20(rewardA).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(rewardAToNative, 0, rewardAToNativeRoute, address(this), now);

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
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)).div(2);

        if (lpToken0 != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeHalf, 0, rewardAToLp0Route, address(this), now);
        }

        if (lpToken1 != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeHalf, 0, rewardAToLp1Route, address(this), now);
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
        return IStakingDualRewards(rewardPool).earnedA(address(this));
    }

    // returns rewards unharvested
    function rewardsBAvailable() public view returns (uint256) {
        uint256 lairReward = IStakingDualRewards(rewardPool).earnedB(address(this));
        return IDragonsLair(dragonsLair).dQUICKForQUICK(lairReward);
    }

    // returns native reward for calling harvest
    function callReward() public view returns (uint256) {
        uint256 rewardABal = rewardsAAvailable();
        uint256 rewardBBal = rewardsBAvailable();

        uint256 nativeOut;

        if (rewardBBal > 0) {
            try IUniswapRouterETH(unirouter).getAmountsOut(rewardBBal, rewardBToRewardARoute)
            returns (uint256[] memory amountOut)
            {
                rewardABal += amountOut[amountOut.length - 1];
            }
            catch {}
        }

        if (rewardABal > 0) {
            try IUniswapRouterETH(unirouter).getAmountsOut(rewardABal, rewardAToNativeRoute)
            returns (uint256[] memory amountOut)
            {
                nativeOut += amountOut[amountOut.length - 1];
            }
            catch {}
        }

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

    function rewardAToNative() public view returns (address[] memory) {
        return rewardAToNativeRoute;
    }

    function rewardBToRewardA() public view returns (address[] memory) {
        return rewardBToRewardARoute;
    }

    function rewardAToLp0() public view returns (address[] memory) {
        return rewardAToLp0Route;
    }

    function rewardAToLp1() public view returns (address[] memory) {
        return rewardAToLp1Route;
    }

    function _giveAllowances() internal {
        IERC20(native).safeApprove(unirouter, uint256(-1));
        IERC20(want).safeApprove(rewardPool, uint256(-1));

        IERC20(rewardA).safeApprove(unirouter, uint256(-1));
        IERC20(rewardB).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(want).safeApprove(rewardPool, 0);

        IERC20(rewardA).safeApprove(unirouter, 0);
        IERC20(rewardB).safeApprove(unirouter, 0);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }
}