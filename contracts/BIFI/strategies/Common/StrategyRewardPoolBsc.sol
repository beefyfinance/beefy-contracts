// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../utils/GasThrottler.sol";
import "./StratManager.sol";
import "./FeeManager.sol";

contract StrategyRewardPoolBsc is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);
    address public want;
    address public output;

    // Third party contracts
    address constant public unirouter = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    address public targetRewardPool;

    // Beefy contracts
    address constant public beefyRewardPool = address(0x453D4Ba9a2D594314DF88564248497F7D74d6b2C);
    address constant public treasury = address(0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01);
    address immutable public vault;

    // Routes
    address[] public outputToWantRoute;
    address[] public outputToWbnbRoute;
    address[] public wbnbToBifiRoute = [wbnb, bifi];

    /*
     @param _want Token to maximize
     @param _output Reward token
     @param targetRewardPool Reward pool to farm
     @param _vault Address of parent vault
     @param _keeper Address of extra maintainer
     @param _strategist Address where stategist fees go.
    */
    constructor(
        address _want,
        address _output,
        address _targetRewardPool,
        address _vault, 
        address _keeper, 
        address _strategist
    ) StratManager(_keeper, _strategist) public {
        want = _want;
        output = _output;
        targetRewardPool = _targetRewardPool;
        vault = _vault;

        if (output != wbnb) {
            outputToWbnbRoute = [output, wbnb];
        }
        
        if (output != want) {
            if (output != wbnb) {
                outputToWantRoute = [output, wbnb, want];
            } else {
                outputToWantRoute = [wbnb, want];
            }   
        }

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IRewardPool(targetRewardPool).deposit(wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IRewardPool(targetRewardPool).withdraw(_amount.sub(wantBal));
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;    
        }
        
        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, wantBal); 
        } else {
            uint256 withdrawalFee = wantBal.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFee)); 
        }
    }

    // compounds earnings and charges performance fee
    function harvest() external whenNotPaused onlyEOA gasThrottle {
        IRewardPool(targetRewardPool).getReward();
        _chargeFees();
        _swapRewards();
        deposit();
    }

    // performance fees
    function _chargeFees() internal {
        if (output != wbnb) {
            uint256 toWbnb = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWbnb, 0, outputToWbnbRoute, address(this), now);
        }
    
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        
        uint256 callFeeAmount = wbnbBal.mul(callFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(msg.sender, callFeeAmount);
        
        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now);
        
        uint256 rewardsFeeAmount = wbnbBal.mul(rewardsFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(beefyRewardPool, rewardsFeeAmount);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    // optionally swaps rewards if output != want.
    function _swapRewards() internal {
        if (output != want) {
            uint256 toWant = IERC20(output).balanceOf(address(this));
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWant, 0, outputToWantRoute, address(this), now);
        }
    }

    // calculate the total underlaying {want} held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much {want} the contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much {want} the strategy has allocated in the {targetRewardPool}
    function balanceOfPool() public view returns (uint256) {
        return IRewardPool(targetRewardPool).balanceOf(address(this));
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardPool(targetRewardPool).withdraw(balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() external onlyManager {
        IRewardPool(targetRewardPool).withdraw(balanceOfPool());
        pause();
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
        IERC20(output).safeApprove(unirouter, uint256(-1));

        if (output != wbnb) {
            IERC20(wbnb).safeApprove(unirouter, uint256(-1));
        }

        IERC20(want).safeApprove(targetRewardPool, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(output).safeApprove(unirouter, 0);

        if (output != wbnb) {
            IERC20(wbnb).safeApprove(unirouter, 0);
        }

        IERC20(want).safeApprove(targetRewardPool, 0);
    }

    function inCaseTokensGetStuck(address _token) external onlyManager {
        require(_token != want, "!safe");
        require(_token != output, "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
