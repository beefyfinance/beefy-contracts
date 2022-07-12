// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/spooky/ISpookyChefV2.sol";
import "../../interfaces/spooky/ISpookyRewarder.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategySpookyV2LP is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public secondOutput;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // Routes
    address[] public outputToNativeRoute;
    address[] public secondOutputToNativeRoute;
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _nativeToLp0Route,
        address[] memory _nativeToLp1Route
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        poolId = _poolId;
        chef = _chef;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

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
    function deposit() public whenNotPaused payable {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            ISpookyChefV2(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external payable {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ISpookyChefV2(chef).withdraw(poolId, _amount.sub(wantBal));
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
    function _harvest(address callFeeRecipient) internal {
        ISpookyChefV2(chef).deposit(poolId, 0);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 secondOutputBal;
        if (secondOutput != address(0)) {
            secondOutputBal = IERC20(secondOutput).balanceOf(address(this));
        }
        if (outputBal > 0 || secondOutputBal > 0) {
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
        uint256 toNative = IERC20(output).balanceOf(address(this));
        if (toNative > 0) {
            IUniswapRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);
        }

        if (secondOutput != address(0)) {
            uint256 secondToNative = IERC20(secondOutput).balanceOf(address(this));
            if (secondToNative > 0) {
                IUniswapRouter(unirouter).swapExactTokensForTokens(secondToNative, 0, secondOutputToNativeRoute, address(this), now);
            }
        }

        uint256 nativeBal = IERC20(native).balanceOf(address(this)).mul(45).div(1000);

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)).div(2);

        if (lpToken0 != native) {
            IUniswapRouter(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp0Route, address(this), now);
        }

        if (lpToken1 != native) {
            IUniswapRouter(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp1Route, address(this), now);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouter(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), now);
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
        (uint256 _amount,) = ISpookyChefV2(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function rewardsAvailable() public view returns (uint256, uint256) {
        uint256 outputBal = ISpookyChefV2(chef).pendingBOO(poolId, address(this));
        uint256 secondBal;
        if (secondOutput != address(0)) {
            address rewarder = ISpookyChefV2(chef).rewarder(poolId);
            secondBal = ISpookyRewarder(rewarder).pendingToken(poolId, address(this));
        }

        return (outputBal, secondBal);
    }

    function callReward() public view returns (uint256) {
        (uint256 outputBal, uint256 secondBal) = rewardsAvailable();
        uint256 nativeBal;

        try IUniswapRouter(unirouter).getAmountsOut(outputBal, outputToNativeRoute)
            returns (uint256[] memory amountOut)
        {
            nativeBal = nativeBal.add(amountOut[amountOut.length -1]);
        }
        catch {}

        if (secondOutput != address(0)) {
            try IUniswapRouter(unirouter).getAmountsOut(secondBal, secondOutputToNativeRoute)
                returns (uint256[] memory amountOut)
            {
                nativeBal = nativeBal.add(amountOut[amountOut.length -1]);
            }
            catch {}
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

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ISpookyChefV2(chef).emergencyWithdraw(poolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ISpookyChefV2(chef).emergencyWithdraw(poolId, address(this));
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
        if (secondOutput != address(0)) {
            IERC20(secondOutput).safeApprove(unirouter, uint256(-1));
        }
        IERC20(native).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, uint256(-1));

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        if (secondOutput != address(0)) {
            IERC20(secondOutput).safeApprove(unirouter, 0);
        }
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    function swapRewardRoute(address[] memory _secondOutputToNativeRoute) external onlyOwner {
        if (secondOutput != address(0) && secondOutput != native && secondOutput != lpToken0 && secondOutput != lpToken1) {
            IERC20(secondOutput).safeApprove(unirouter, 0);
        }
        require(_secondOutputToNativeRoute[_secondOutputToNativeRoute.length - 1] == native,
            "_secondOutputToNativeRoute[last] != native");

        secondOutput = _secondOutputToNativeRoute[0];
        secondOutputToNativeRoute = _secondOutputToNativeRoute;

        IERC20(secondOutput).safeApprove(unirouter, 0);
        IERC20(secondOutput).safeApprove(unirouter, uint256(-1));
    }

    function removeRewardRoute() external onlyManager {
        if (secondOutput != address(0) && secondOutput != native && secondOutput != lpToken0 && secondOutput != lpToken1) {
            IERC20(secondOutput).safeApprove(unirouter, 0);
        }
        secondOutput = address(0);
        delete secondOutputToNativeRoute;
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function secondOutputToNative() external view returns (address[] memory) {
        return secondOutputToNativeRoute;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return nativeToLp0Route;
    }

    function nativeToLp1() external view returns (address[] memory) {
        return nativeToLp1Route;
    }
}
