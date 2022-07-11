// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterSolidly.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/ISolidlyGauge.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/GasThrottler.sol";

contract StrategyCommonSolidlyGaugeLP is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public gauge;
    address public intializer;

    bool public stable;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    
    IUniswapRouterSolidly.Routes[] public outputToNativeRoute;
    IUniswapRouterSolidly.Routes[] public outputToLp0Route;
    IUniswapRouterSolidly.Routes[] public outputToLp1Route;
    address[] public rewards;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        address _gauge,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        gauge = _gauge;

        stable = ISolidlyPair(want).stable();
        intializer = msg.sender;
    }

    function intializeRoutes(address[][] memory outputToNative, address[][] memory outputToLp0, address[][] memory outputToLp1, bool[][] memory stables) external onlyOwner {
        require(intializer != address(0), "Already Intialized");
        
        _initOutputToNativeRoute(outputToNative, stables[0]);
        _initOutputToLp0Route(outputToLp0, stables[1]);
        _initOutputToLp1Route(outputToLp1, stables[2]);

        output = outputToNativeRoute[0].from;
        native = outputToNativeRoute[outputToNativeRoute.length -1].to;
        lpToken0 = outputToLp0Route[outputToLp0Route.length - 1].to;
        lpToken1 = outputToLp1Route[outputToLp1Route.length - 1].to;

        rewards.push(output);
        _giveAllowances();

        intializer = address(0);
    }

    function _initOutputToNativeRoute(address[][] memory tokens, bool[] memory stables) internal {
        for (uint i; i < tokens.length; ++i) {
            outputToNativeRoute.push(IUniswapRouterSolidly.Routes({
                from: tokens[i][0],
                to: tokens[i][1],
                stable: stables[i]
            }));
        }
    }

    function _initOutputToLp0Route(address[][] memory tokens, bool[] memory stables) internal {
        for (uint i; i < tokens.length; ++i) {
            outputToLp0Route.push(IUniswapRouterSolidly.Routes({
                from: tokens[i][0],
                to: tokens[i][1],
                stable: stables[i]
            }));
        }
    }

     function _initOutputToLp1Route(address[][] memory tokens, bool[] memory stables) internal {
        for (uint i; i < tokens.length; ++i) {
            outputToLp1Route.push(IUniswapRouterSolidly.Routes({
                from: tokens[i][0],
                to: tokens[i][1],
                stable: stables[i]
            }));
        }
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            ISolidlyGauge(gauge).deposit(wantBal, 0);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ISolidlyGauge(gauge).withdraw(_amount.sub(wantBal));
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

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external gasThrottle virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        ISolidlyGauge(gauge).getReward(address(this), rewards);
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
        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterSolidly(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 lp0Amt;
        uint256 lp1Amt;
        if (stable) {
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            lp0Amt = outputBal.mul(getRatio()).div(10**18);
            lp1Amt = outputBal.sub(lp0Amt);
        } else { 
            lp0Amt = IERC20(output).balanceOf(address(this)).div(2);
            lp1Amt = lp0Amt;
        }

        if (lpToken0 != output) {
            IUniswapRouterSolidly(unirouter).swapExactTokensForTokens(lp0Amt, 0, outputToLp0Route, address(this), now);
        }

        if (lpToken1 != output) {
            IUniswapRouterSolidly(unirouter).swapExactTokensForTokens(lp1Amt, 0, outputToLp1Route, address(this), now);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouterSolidly(unirouter).addLiquidity(lpToken0, lpToken1, stable, lp0Bal, lp1Bal, 1, 1, address(this), now);
    }

    function getRatio() public view returns (uint256) {
        (uint256 opLp0, uint256 opLp1, ) = ISolidlyPair(want).getReserves();
        uint256 lp0Amt = opLp0.mul(10**18).div(10**IERC20Extended(lpToken0).decimals());
        uint256 lp1Amt = opLp1.mul(10**18).div(10**IERC20Extended(lpToken1).decimals());   
        uint256 totalSupply = lp0Amt.add(lp1Amt);      
        return lp0Amt.mul(10**18).div(totalSupply);
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
        return ISolidlyGauge(gauge).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return ISolidlyGauge(gauge).earned(output, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            (nativeOut,) = IUniswapRouterSolidly(unirouter).getAmountOut(outputBal, output, native);
            }

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ISolidlyGauge(gauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ISolidlyGauge(gauge).withdraw(balanceOfPool());
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
        IERC20(want).safeApprove(gauge, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(gauge, 0);
        IERC20(output).safeApprove(unirouter, 0);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }
}