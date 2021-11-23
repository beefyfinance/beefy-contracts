// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/sushi/IRewarder.sol";
import "../../interfaces/synapse/IMiniChefV2.sol";
import "../../interfaces/synapse/ISwapFlashLoan.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategySynapseStableswap is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address constant nullAddress = address(0);

    // Tokens used
    IERC20 public native;
    IERC20 public output;
    IERC20 public want;
    IERC20 public stable;

    // Third party contracts
    ISwapFlashLoan public swap; // for adding liquidity
    uint256 public poolTokenCount = 4;
    uint8 public depositIndex;
    IMiniChefV2 public chef;
    uint256 public poolId;

    uint256 public lastHarvest;
    bool public harvestOnDeposit;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToStableRoute;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

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
        address[] memory _outputToStableRoute,
        address _swap
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = IERC20(_want);
        poolId = _poolId;
        chef = IMiniChefV2(_chef);
        swap = ISwapFlashLoan(_swap);

        require(_outputToNativeRoute.length >= 2);
        output = IERC20(_outputToNativeRoute[0]);
        native = IERC20(_outputToNativeRoute[_outputToNativeRoute.length - 1]);
        outputToNativeRoute = _outputToNativeRoute;
        
        _setOutputToStableRoute(_outputToStableRoute);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = want.balanceOf(address(this));

        if (wantBal > 0) {
            chef.deposit(poolId, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = want.balanceOf(address(this));

        if (wantBal < _amount) {
            chef.withdraw(poolId, _amount.sub(wantBal), address(this));
            wantBal = want.balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            wantBal = wantBal.sub(withdrawalFeeAmount);
        }

        want.safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        require(msg.sender == vault, "!vault");
        if (harvestOnDeposit) {
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
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        chef.harvest(poolId, address(this));
        uint256 outputBal = output.balanceOf(address(this));
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
        uint256 toNative = output.balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);

        uint256 nativeBal = native.balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        native.safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        native.safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        native.safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 toStable = output.balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toStable, 0, outputToStableRoute, address(this), block.timestamp);

        uint256 stableBalance = stable.balanceOf(address(this));
        uint256[] memory amounts = new uint256[](poolTokenCount);
        amounts[depositIndex] = stableBalance;
        swap.addLiquidity(amounts, 0, block.timestamp);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = chef.userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        chef.emergencyWithdraw(poolId, address(this));

        uint256 wantBal = want.balanceOf(address(this));
        want.transfer(vault, wantBal);
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return chef.pendingSynapse(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
         if (outputBal > 0) {
            try IUniswapRouterETH(unirouter).getAmountsOut(outputBal, outputToNativeRoute)
                returns (uint256[] memory amountOut) 
            {
                nativeOut = amountOut[amountOut.length -1];
            }
            catch {}
        }

        uint256 pendingNative;
        address rewarder = chef.rewarder(poolId);
        if (rewarder != nullAddress) {
            pendingNative = IRewarder(rewarder).pendingToken(poolId, address(this));
        } 

        return pendingNative.add(nativeOut).mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        chef.emergencyWithdraw(poolId, address(this));
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
        want.safeApprove(address(chef), type(uint256).max);
        output.safeApprove(unirouter, type(uint256).max);

        stable.safeApprove(unirouter, 0);
        stable.safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        want.safeApprove(address(chef), 0);
        output.safeApprove(unirouter, 0);

        stable.safeApprove(unirouter, 0);
        stable.safeApprove(unirouter, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToStable() external view returns (address[] memory) {
        return outputToStableRoute;
    }

    function setOutputToStableRoute(address[] memory _outputToStableRoute) external onlyManager {
        stable.safeApprove(unirouter, 0);
        stable.safeApprove(unirouter, 0);

        _setOutputToStableRoute(_outputToStableRoute);

        stable.safeApprove(unirouter, 0);
        stable.safeApprove(unirouter, type(uint256).max);
    }

    // to allow switching of stable to use for adding liquidity
    function _setOutputToStableRoute(address[] memory _outputToStableRoute) internal {
        require(_outputToStableRoute[0] == address(output), 'first != output');
        stable = IERC20(_outputToStableRoute[_outputToStableRoute.length - 1]);
        depositIndex = swap.getTokenIndex(address(stable)); // will revert if doesn't exist
        outputToStableRoute = _outputToStableRoute;
    }
}
