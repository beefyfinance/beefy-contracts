// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/auto/IAutoFarmV2.sol";
import "../../interfaces/belt/IBeltLP.sol";
import "../../utils/GasThrottler.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyAuto4Belt is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public Auto = address(0xa184088a740c695E156F91f5cC086a06bb78b827);
    address constant public busd = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    address constant public want = address(0x9cb73F20164e399958261c289Eb5F9846f4D1404);

    // Third party contracts
    address constant public autofarm = address(0x0895196562C7868C5Be92459FaE7f877ED450452);
    address constant public beltLP   = address(0xF6e65B33370Ee6A49eB0dbCaA9f43839C1AC04d5);
    uint256 constant public poolId = 341;

    // Routes
    address[] public AutoToWbnbRoute = [Auto, wbnb];
    address[] public AutoToBusdRoute = [Auto, wbnb, busd];

    /**
     * @dev If rewards are locked in AutoFarm, retire() will use emergencyWithdraw.
     */
    bool public rewardsLocked = false;

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
            IAutoFarmV2(autofarm).deposit(poolId, wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IAutoFarmV2(autofarm).withdraw(poolId, _amount.sub(wantBal));
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

    // compounds earnings and charges performance fee
    function harvest() external whenNotPaused gasThrottle {
        IAutoFarmV2(autofarm).deposit(poolId, 0);
        chargeFees();
        addLiquidity();
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees() internal {
        uint256 toWbnb = IERC20(Auto).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWbnb, 0, AutoToWbnbRoute, address(this), now);

        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 callFeeAmount = wbnbBal.mul(callFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = wbnbBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 autoBal = IERC20(Auto).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(autoBal, 0, AutoToBusdRoute, address(this), now);

        uint256 busdBal = IERC20(busd).balanceOf(address(this));
        uint256[4] memory uamounts = [0, 0, 0, busdBal];
        IBeltLP(beltLP).add_liquidity(uamounts, 0);
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
        return IAutoFarmV2(autofarm).stakedWantTokens(poolId, address(this));
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        if (rewardsLocked) {
            _retireStratEmergency();
        } else {
            _retireStrat();
        }
    }

    function setRewardsLocked(bool _rewardsLocked) external onlyOwner {
        rewardsLocked = _rewardsLocked;
    }

    function _retireStrat() internal {
        IAutoFarmV2(autofarm).withdraw(poolId, uint(-1));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    function _retireStratEmergency() internal {
        IAutoFarmV2(autofarm).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IAutoFarmV2(autofarm).withdraw(poolId, uint(-1));
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panicEmergency() public onlyManager {
        pause();
        IAutoFarmV2(autofarm).emergencyWithdraw(poolId);
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
        IERC20(want).safeApprove(autofarm, uint(-1));
        IERC20(Auto).safeApprove(unirouter, uint(-1));
        IERC20(busd).safeApprove(beltLP, uint(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(autofarm, 0);
        IERC20(Auto).safeApprove(unirouter, 0);
        IERC20(busd).safeApprove(beltLP, 0);
    }
}
