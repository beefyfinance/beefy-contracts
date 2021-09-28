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
    address public want;
    address public output;

    // Third party contracts
    address public rewardPool;

    uint256 public lastHarvest;

    // Routes
    address[] public outputToWantRoute;
    address[] public outputToWbnbRoute;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _want,
        address _output,
        address _rewardPool,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        output = _output;
        rewardPool = _rewardPool;

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
            IRewardPool(rewardPool).deposit(wantBal);
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

        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, wantBal);
        } else {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFeeAmount));
        }
    }

    // compounds earnings and charges performance fee
    function harvest() external whenNotPaused gasThrottle {
        IRewardPool(rewardPool).getReward();
        _chargeFees();
        _swapRewards();
        deposit();

        lastHarvest = block.timestamp;
        emit StratHarvest(msg.sender);
    }

    // performance fees
    function _chargeFees() internal {
        uint256 wbnbBal;

        if (output != wbnb) {
            uint256 toWbnb = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWbnb, 0, outputToWbnbRoute, address(this), now);
            wbnbBal = IERC20(wbnb).balanceOf(address(this));
        } else {
            wbnbBal = IERC20(wbnb).balanceOf(address(this)).mul(45).div(1000);
        }

        uint256 callFeeAmount = wbnbBal.mul(callFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = wbnbBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

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
        return IRewardPool(rewardPool).balanceOf(address(this));
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardPool(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() external onlyManager {
        IRewardPool(rewardPool).withdraw(balanceOfPool());
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
        IERC20(want).safeApprove(rewardPool, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function inCaseTokensGetStuck(address _token) external onlyManager {
        require(_token != want, "!safe");
        require(_token != output, "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}
