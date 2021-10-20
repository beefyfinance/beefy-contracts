// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMultiFeeDistribution.sol";
import "../../interfaces/ellipsis/IEpsLP.sol";
import "../../interfaces/ellipsis/ILpStaker.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyFroyo3Pool is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wftm = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address constant public output = address(0xA92d41Ab8eFeE617d80a829CD9F5683c5F793ADA);
    address constant public dai = address(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E);
    address constant public want = address(0x4f85Bbf3B0265DCEd4Ec72ebD0358ccCf190F1B3);

    // Third party contracts
    address constant public stakingPool     = address(0x93b1531Ca2d6595e6bEE8bd3d306Fcdad5775CDE);
    address constant public feeDistribution = address(0xBcd49db69b9eda8c02c8963ED39b1f14a54BF405);
    address constant public poolLp          = address(0x83E5f18Da720119fF363cF63417628eB0e9fd523);
    uint8 constant public poolId = 1;

    // Routes
    address[] public outputToWftmRoute = [output, wftm];
    address[] public outputToDaiRoute = [output, wftm, dai];

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
            ILpStaker(stakingPool).deposit(poolId, wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ILpStaker(stakingPool).withdraw(poolId, _amount.sub(wantBal));
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
    function harvest() external whenNotPaused {
        uint256[] memory pids = new uint256[](1);
        pids[0] = poolId;
        ILpStaker(stakingPool).claim(pids);
        IMultiFeeDistribution(feeDistribution).exit();

        chargeFees();
        addLiquidity();
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees() internal {
        uint256 toWftm = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWftm, 0, outputToWftmRoute, address(this), now);

        uint256 wftmBal = IERC20(wftm).balanceOf(address(this));

        uint256 callFeeAmount = wftmBal.mul(callFee).div(MAX_FEE);
        IERC20(wftm).safeTransfer(msg.sender, callFeeAmount);

        uint256 beefyFeeAmount = wftmBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wftm).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wftmBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wftm).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToDaiRoute, address(this), now);

        uint256 daiBal = IERC20(dai).balanceOf(address(this));
        uint256[3] memory amounts = [0, daiBal, 0];
        IEpsLP(poolLp).add_liquidity(amounts, 0);
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
        (uint256 _amount, ) = ILpStaker(stakingPool).userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ILpStaker(stakingPool).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ILpStaker(stakingPool).emergencyWithdraw(poolId);
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
        IERC20(want).safeApprove(stakingPool, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(dai).safeApprove(poolLp, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(stakingPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(dai).safeApprove(poolLp, 0);
    }
}