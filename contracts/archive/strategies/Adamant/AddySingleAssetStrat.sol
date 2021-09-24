// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMultiFeeDistribution.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract AddySingleAssetStrat is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public eth = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    address constant public matic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address constant public quick = address(0x831753DD7087CaC61aB5644b308642cc1c33Dc13);
    address public want;

    // Third party contracts
    address public rewardPool;

    // Routes
    address[] public quickToAddyRoute;
    address[] public quickToMaticRoute = [quick, matic];

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _want,
        address _rewardPool,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        rewardPool = _rewardPool;

        quickToAddyRoute = [quick, eth, want];

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMultiFeeDistribution(rewardPool).stake(wantBal, false);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMultiFeeDistribution(rewardPool).withdraw(_amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, wantBal);
        } else {
            uint256 withdrawalFee = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFee));
        }
    }

    // compounds earnings and charges performance fee
    function harvest() external whenNotPaused {
        IMultiFeeDistribution(rewardPool).getReward();
        chargeFees();
        swapRewards();
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees() internal {
        uint256 toMatic = IERC20(quick).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toMatic, 0, quickToMaticRoute, address(this), now);

        uint256 maticBal = IERC20(matic).balanceOf(address(this));

        uint256 callFeeAmount = maticBal.mul(callFee).div(MAX_FEE);
        IERC20(matic).safeTransfer(msg.sender, callFeeAmount);

        uint256 beefyFeeAmount = maticBal.mul(beefyFee).div(MAX_FEE);
        IERC20(matic).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = maticBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(matic).safeTransfer(strategist, strategistFee);
    }

    // swap rewards to {want}
    function swapRewards() internal {
        uint256 quickBalance = IERC20(quick).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(quickBalance, 0, quickToAddyRoute, address(this), now);
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
        return IMultiFeeDistribution(rewardPool).totalBalance(address(this));
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMultiFeeDistribution(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMultiFeeDistribution(rewardPool).withdraw(balanceOfPool());
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
        IERC20(quick).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(quick).safeApprove(unirouter, 0);
    }
}