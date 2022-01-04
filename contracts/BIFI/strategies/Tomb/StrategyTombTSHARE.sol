// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/tomb/IMasonry.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyTombTSHARE is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;

    // Third party contracts
    IMasonry public masonry;

    uint256 public lastHarvest;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToWantRoute;

    // Lock Toggles & Epoch info
    bool public locked = false;
    bool public initiateTimelock;
    uint256 public depositTime;
    uint256 public withdrawTime;
    uint256 public withdrawPeriod = 7200; // 2 Hours to withdraw before next lock
    uint256 public withdrawEpochs = 6; // Each Epoch is 6 hours

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _want,
        IMasonry _masonry,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantRoute
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        masonry = _masonry;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        require(_outputToWantRoute[0] == output, "outputToWantRoute[0] != output");
        require(_outputToWantRoute[_outputToWantRoute.length - 1] == want, "outputToWantRoute[last] != want");
        outputToWantRoute = _outputToWantRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        if (initiateTimelock) {
            uint256 wantBal = IERC20(want).balanceOf(address(this));
            masonry.stake(wantBal);
            depositTime = block.timestamp;
            initiateTimelock = false;
        }

        checkEpoch();
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        require(!locked, "Withdrawals locked");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            masonry.withdraw(_amount.sub(wantBal));
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

    // checks to ensure that the correct time has elapsed and withdrawals are possible
    function checkEpoch() internal returns (bool locking) {        
        if (masonry.canWithdraw(address(this)) && locked) {
            startUnlockWindow();
            locking = false;
        } else if (block.timestamp > withdrawTime.add(withdrawPeriod) && !locked) {
            locked = true;
            initiateTimelock = true;
            _harvest(tx.origin);
            locking = true;
        } else {
            locking = false;
        }
    }

    function startUnlockWindow() internal {
        // withdraw all tshare from the masonry
        if (masonry.balanceOf(address(this)) > 0) {
            masonry.exit();
        }
        // initiate the withdrawal window
        withdrawTime = block.timestamp;
        // unlock controller
        locked = false;
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            uint256[] memory swapAmounts = swapRewards();
            uint256 wantHarvested = swapAmounts[1];
            deposit();
            
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
    }

    // Swaps Output for more Want
    function swapRewards() internal returns (uint256[] memory amounts) {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        amounts = IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantRoute, address(this), now);
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
        return masonry.balanceOf(address(this));
    }

   function unlockWindowRemaining() public view returns (uint256 timeLeft) {
        timeLeft = (withdrawTime + withdrawPeriod) - block.timestamp;
        if (timeLeft > withdrawPeriod) {
            timeLeft = 0;
        }
        timeLeft;
    }

    function canWithdrawEpoch() public view returns (uint256 withdrawEpoch) {
        (,,uint256 epochStart) = masonry.masons(address(this));
        withdrawEpoch = epochStart.add(withdrawEpochs);
    }

    function lockWindowRemaining() public view returns (uint256 timeLeft) {
        uint256 currentEpoch = masonry.epoch();
        uint256 withdrawEpoch = canWithdrawEpoch();
        if (withdrawEpoch > currentEpoch) {
            uint256 epochsLeft = withdrawEpoch.sub(currentEpoch).sub(1);
            uint256 timeToNextEpoch = masonry.nextEpochPoint().sub(block.timestamp);
            timeLeft = epochsLeft.mul(21600).add(timeToNextEpoch); // one epoch is 6 hours
        } else {
            timeLeft = 0;
        }
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
       return masonry.earned(address(this));
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

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        masonry.exit();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        masonry.exit();
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
        IERC20(want).safeApprove(address(masonry), uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(address(masonry), 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToWant() external view returns (address[] memory) {
        return outputToWantRoute;
    }
}
