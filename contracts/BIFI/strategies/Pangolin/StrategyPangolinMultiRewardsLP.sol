// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/pangolin/IPangolinMiniChef.sol";
import "../../interfaces/pangolin/IPangolinRewarder.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyPangolinMultiRewardsLP is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address constant nullAddress = address(0);

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address constant public chef = address(0x1f806f7C8dED893fd3caE279191ad7Aa3798E928);
    uint256 public poolId;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;

    // Routes
    address[] public outputToNativeRoute;
    address[][] public rewardToNativeRoutes;
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _want,
        uint256 _poolId,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[][] memory _rewardToNativeRoutes,
        address[] memory _nativeToLp0Route,
        address[] memory _nativeToLp1Route
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        poolId = _poolId;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;
        rewardToNativeRoutes = _rewardToNativeRoutes;

        // setup lp routing
        lpToken0 = IUniswapV2Pair(want).token0();
        require(_nativeToLp0Route[0] == native, "nativeToLp0Route[0] != native");
        require(_nativeToLp0Route[_nativeToLp0Route.length - 1] == lpToken0, "nativeToLp0Route[last] != lpToken0");
        nativeToLp0Route = _nativeToLp0Route;

        lpToken1 = IUniswapV2Pair(want).token1();
        require(_nativeToLp1Route[0] == native, "nativeToLp1Route[0] != native");
        require(_nativeToLp1Route[_nativeToLp1Route.length - 1] == lpToken1, "nativeToLp1Route[last] != lpToken1");
        nativeToLp1Route = _nativeToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IPangolinMiniChef(chef).deposit(poolId, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IPangolinMiniChef(chef).withdraw(poolId, _amount.sub(wantBal), address(this));
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

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IPangolinMiniChef(chef).harvest(poolId, address(this));
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
        if (rewardToNativeRoutes.length != 0) {
            for (uint i; i < rewardToNativeRoutes.length; i++) {
                uint256 rewardBal = IERC20(rewardToNativeRoutes[i][0]).balanceOf(address(this));
                if (rewardBal > 0) {
                    IUniswapRouterETH(unirouter).swapExactTokensForTokens(rewardBal, 0, rewardToNativeRoutes[i], address(this), now);
                }
            }
        }

        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToNativeRoute, address(this), now);
        }
        
        uint256 nativeBal = IERC20(native).balanceOf(address(this)).mul(45).div(1000);

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
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp0Route, address(this), block.timestamp);
        }

        if (lpToken1 != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp1Route, address(this), block.timestamp);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouterETH(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
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
        (uint256 _amount, ) = IPangolinMiniChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IPangolinMiniChef(chef).emergencyWithdraw(poolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // returns secondary rewards unharvested
    function rewardsAvailable() public view returns (uint256, uint256[] memory) {
        uint256 pngReward = IPangolinMiniChef(chef).pendingReward(poolId, address(this));
        uint256[] memory secondaryRewards;
        // checks if there is a rewarder associated with the pool, if not will return an empty array.
        address rewarder = IPangolinMiniChef(chef).rewarder(poolId);
        if (rewarder != nullAddress) {
        (, uint256[] memory amounts) = IPangolinRewarder(rewarder).pendingTokens(poolId, address(this), pngReward);
            secondaryRewards = amounts;
        }

        return (pngReward, secondaryRewards);
    }

    function callReward() public view returns (uint256) {
        (uint256 pngReward, uint256[] memory secondaryRewards) = rewardsAvailable();
        uint256 nativeBal;
        try IUniswapRouterETH(unirouter).getAmountsOut(pngReward, outputToNativeRoute)
            returns (uint256[] memory amountOut) 
        {
            nativeBal = amountOut[amountOut.length -1];
        }
        catch {}

        if (rewardToNativeRoutes.length != 0) {
            for (uint i; i < rewardToNativeRoutes.length; i++) {
                try IUniswapRouterETH(unirouter).getAmountsOut(secondaryRewards[i], rewardToNativeRoutes[i])
                returns (uint256[] memory rewardAmount)
                {
                    nativeBal += rewardAmount[rewardAmount.length - 1];
                } catch {}
            }
        }

        return nativeBal.mul(45).div(1000).mul(callFee).div(MAX_FEE);
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
        IPangolinMiniChef(chef).emergencyWithdraw(poolId, address(this));
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
        IERC20(native).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, uint256(-1));

        if (rewardToNativeRoutes.length != 0) {
            for (uint i; i < rewardToNativeRoutes.length; i++) {
                IERC20(rewardToNativeRoutes[i][0]).safeApprove(unirouter, 0);
                IERC20(rewardToNativeRoutes[i][0]).safeApprove(unirouter, uint256(-1));
            }
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);

        if (rewardToNativeRoutes.length != 0) {
            for (uint i; i < rewardToNativeRoutes.length; i++) {
                IERC20(rewardToNativeRoutes[i][0]).safeApprove(unirouter, 0);
            }
        }
    }

    function addRewardRoute(address[] memory _rewardToNativeRoute) external onlyManager {
        IERC20(_rewardToNativeRoute[0]).safeApprove(unirouter, 0);
        IERC20(_rewardToNativeRoute[0]).safeApprove(unirouter, uint256(-1));
        rewardToNativeRoutes.push(_rewardToNativeRoute);
    }

    function removeLastRewardRoute() external onlyManager {
        address reward = rewardToNativeRoutes[rewardToNativeRoutes.length - 1][0];
        if (reward != lpToken0 && reward != lpToken1) {
            IERC20(reward).safeApprove(unirouter, 0);
        }
        rewardToNativeRoutes.pop();
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return nativeToLp0Route;
    }

    function nativeToLp1() external view returns (address[] memory) {
        return nativeToLp1Route;
    }
    
    function reward0ToNative() external view returns (address[] memory) {
        return rewardToNativeRoutes[0];
    }

    function reward1ToNative() external view returns (address[] memory) {
        return rewardToNativeRoutes[1];
    }
}