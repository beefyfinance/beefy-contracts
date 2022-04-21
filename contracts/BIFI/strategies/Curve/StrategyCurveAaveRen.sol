// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyCurveAaveRen is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address constant public btc = address(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6);
    address constant public crv = address(0x172370d5Cd63279eFa6d502DAB29171933a610AF);
    address constant public eth = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    address constant public want = address(0xf8a57c1d3b9629b77b6726a042ca48990A84Fb49);

    // Third party contracts
    address constant public swapToken = address(0xC2d95EEF97Ec6C17551d45e77B590dc1F9117C67);
    address constant public rewards = address(0xffbACcE0CC7C19d46132f1258FC16CF6871D153c);

    // Routes
    address[] public wmaticToBtcRoute = [wmatic, eth, btc];
    address[] public crvToWmaticRoute = [crv, eth, wmatic];

    bool public harvestOnDeposit = false;

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
            IRewardsGauge(rewards).deposit(wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IRewardsGauge(rewards).withdraw(_amount.sub(wantBal));
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
        if (harvestOnDeposit) {
            harvest();
        }
    }

    // compounds earnings and charges performance fee
    function harvest() public whenNotPaused {
        require(tx.origin == msg.sender || msg.sender == vault, "!contract");
        IRewardsGauge(rewards).claim_rewards(address(this));

        uint256 crvBal = IERC20(crv).balanceOf(address(this));
        uint256 wmaticBal = IERC20(wmatic).balanceOf(address(this));
        if (wmaticBal > 0 || crvBal > 0) {
            chargeFees();
            addLiquidity();
            deposit();
            emit StratHarvest(msg.sender);
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 crvBal = IERC20(crv).balanceOf(address(this));
        if (crvBal > 0) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(crvBal, 0, crvToWmaticRoute, address(this), block.timestamp);
        }

        uint256 wmaticFeeBal = IERC20(wmatic).balanceOf(address(this)).mul(45).div(1000);

        uint256 callFeeAmount = wmaticFeeBal.mul(callFee).div(MAX_FEE);
        IERC20(wmatic).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = wmaticFeeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wmatic).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wmaticFeeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wmatic).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 wmaticBal = IERC20(wmatic).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(wmaticBal, 0, wmaticToBtcRoute, address(this), block.timestamp);

        uint256 btcBal = IERC20(btc).balanceOf(address(this));
        uint256[2] memory amounts = [btcBal, 0];
        ICurveSwap(swapToken).add_liquidity(amounts, 0, true);
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
        return IRewardsGauge(rewards).balanceOf(address(this));
    }

    function setHarvestOnDeposit(bool _harvest) external onlyManager {
        harvestOnDeposit = _harvest;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardsGauge(rewards).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IRewardsGauge(rewards).withdraw(balanceOfPool());
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
        IERC20(want).safeApprove(rewards, type(uint).max);
        IERC20(wmatic).safeApprove(unirouter, type(uint).max);
        IERC20(crv).safeApprove(unirouter, type(uint).max);
        IERC20(btc).safeApprove(swapToken, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewards, 0);
        IERC20(wmatic).safeApprove(unirouter, 0);
        IERC20(crv).safeApprove(unirouter, 0);
        IERC20(btc).safeApprove(swapToken, 0);
    }
}
