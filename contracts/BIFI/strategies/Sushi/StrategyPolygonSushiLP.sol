// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/sushi/IUniswapV2Router02.sol";
import "../../interfaces/sushi/IUniswapV2Pair.sol";
import "../../interfaces/sushi/IMiniChefV2.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyPolygonSushiLP is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public eth = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    address constant public matic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address constant public output = address(0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a);
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address constant public minichef = address(0x0769fd68dFb93167989C6f7254cd0D766Fb2841F);	
    uint256 public poolId;

    // Routes
    address[] public outputToMaticRoute = [output, matic];
    address[] public maticToOutputRoute = [matic, output];
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _want,
        uint256 _poolId,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        lpToken0 = IUniswapV2Pair(want).token0();
        lpToken1 = IUniswapV2Pair(want).token1();
        poolId = _poolId;

        if (lpToken0 == matic) {
            outputToLp0Route = [output, matic];
        } else if (lpToken0 == eth) {
            outputToLp0Route = [output, eth];
        } else if (lpToken0 != output) {
            outputToLp0Route = [output, matic, eth, lpToken0];
        }

        if (lpToken1 == matic) {
            outputToLp1Route = [output, matic];
        } else if (lpToken1 == eth) {
            outputToLp1Route = [output, eth];
        } else if (lpToken1 != output) {
            outputToLp1Route = [output, matic, eth, lpToken1];
        }

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMiniChefV2(minichef).deposit(poolId, wantBal, address(this));
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMiniChefV2(minichef).withdraw(poolId, _amount.sub(wantBal), address(this));
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
    function harvest() external whenNotPaused onlyEOA {
        IMiniChefV2(minichef).harvest(poolId, address(this));
        chargeFees();
        addLiquidity();
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees() internal {
        // v2 harvester rewards are in both sushi and matic, convert matic to sushi
        uint256 maticToOutput = IERC20(matic).balanceOf(address(this));
        if (maticToOutput > 0) {
            IUniswapV2Router02(unirouter).swapExactTokensForTokens(maticToOutput, 0, maticToOutputRoute, address(this), now);
        }
        
        uint256 toMatic = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapV2Router02(unirouter).swapExactTokensForTokens(toMatic, 0, outputToMaticRoute, address(this), now);

        uint256 maticBal = IERC20(matic).balanceOf(address(this));

        uint256 callFeeAmount = maticBal.mul(callFee).div(MAX_FEE);
        IERC20(matic).safeTransfer(msg.sender, callFeeAmount);

        uint256 beefyFeeAmount = maticBal.mul(beefyFee).div(MAX_FEE);
        IERC20(matic).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = maticBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(matic).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputHalf = IERC20(output).balanceOf(address(this)).div(2);

        if (lpToken0 != output) {
            IUniswapV2Router02(unirouter).swapExactTokensForTokens(outputHalf, 0, outputToLp0Route, address(this), now);
        }

        if (lpToken1 != output) {
            IUniswapV2Router02(unirouter).swapExactTokensForTokens(outputHalf, 0, outputToLp1Route, address(this), now);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapV2Router02(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), now);
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
        (uint256 _amount, ) = IMiniChefV2(minichef).userInfo(poolId, address(this));	
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMiniChefV2(minichef).emergencyWithdraw(poolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMiniChefV2(minichef).emergencyWithdraw(poolId, address(this));
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
        IERC20(want).safeApprove(minichef, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        // needed for v2 harvester
        IERC20(matic).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(minichef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }
}
