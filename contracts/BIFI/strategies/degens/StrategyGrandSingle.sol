// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/grand/IGrandFarm.sol";
import "../../interfaces/grand/IWrappedGrand.sol";
import "../../utils/GasThrottler.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyGrandSingle is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public want = address(0xeE814F5B2bF700D2e843Dc56835D28d095161dd9);
    address constant public wrappedGrand = address(0x28060854AC19391dF6C69Df430cAba4506181d56);

    // Third party contracts
    address constant public masterchef = address(0x3d8fd880976a3EA0f53cad02463867013D331107);
    uint256 constant public poolId = 22;

    // Routes
    address[] public wantToWbnbRoute = [want, wbnb];

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IWrappedGrand(wrappedGrand).deposit(wantBal);
            IGrandFarm(masterchef).depositWant(poolId, wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IGrandFarm(masterchef).withdrawWant(poolId, _amount.sub(wantBal));
            IWrappedGrand(wrappedGrand).withdraw(_amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
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

    function beforeDeposit() external override {
        harvest();
    }

    // compounds earnings and charges performance fee
    function harvest() public whenNotPaused gasThrottle {
        require(tx.origin == msg.sender || msg.sender == vault, "!contract");
        IGrandFarm(masterchef).depositWant(poolId, 0);
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            chargeFees();
            deposit();
            emit StratHarvest(msg.sender);
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 toWbnb = IERC20(want).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWbnb, 0, wantToWbnbRoute, address(this), now);

        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 callFeeAmount = wbnbBal.mul(callFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = wbnbBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
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
        return IGrandFarm(masterchef).stakedWantTokens(poolId, address(this));
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IGrandFarm(masterchef).emergencyWithdraw(poolId);
        uint256 wrappedBal = IERC20(wrappedGrand).balanceOf(address(this));
        IWrappedGrand(wrappedGrand).withdraw(wrappedBal);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IGrandFarm(masterchef).emergencyWithdraw(poolId);
        uint256 wrappedBal = IERC20(wrappedGrand).balanceOf(address(this));
        IWrappedGrand(wrappedGrand).withdraw(wrappedBal);
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
        IERC20(want).safeApprove(wrappedGrand, uint256(-1));
        IERC20(wrappedGrand).safeApprove(masterchef, uint256(-1));
        IERC20(want).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(wrappedGrand, 0);
        IERC20(wrappedGrand).safeApprove(masterchef, 0);
        IERC20(want).safeApprove(unirouter, 0);
    }
}