// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IERC20Extended.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/solace/ISolaceRewards.sol";
import "../../interfaces/solace/IxLocker.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/GasThrottler.sol";

contract StrategySolaceRewardPool is  StratManager, FeeManager, GasThrottler, IERC721Receiver {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;

    // Third party contracts
    ISolaceRewards public rewardPool;
    IxLocker public xLocker;

    // Our locker ID 
    uint256 public lockerID;

    // Harvest data
    bool public chargedFees = false;
    bool public harvested = false;
    uint256 public harvestedBal;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToWantRoute;

    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);


    constructor(
        address _want,
        address _rewardPool,
        address _xLocker,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        rewardPool = ISolaceRewards(_rewardPool);
        xLocker = IxLocker(_xLocker);

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant().sub(harvestedBal);

        if (wantBal > 0) {
            if (lockerID == 0) {
                lockerID = xLocker.createLock(address(this), wantBal, 0);
                emit Deposit(balanceOf());
            } else {
                xLocker.increaseAmount(lockerID, wantBal);
                harvestedBal = balanceOfWant();
                emit Deposit(balanceOf());
            }
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant().sub(harvestedBal);

        if (wantBal < _amount) {
            uint256 before = balanceOfWant();
            xLocker.withdrawInPart(lockerID, address(this), _amount.sub(wantBal));
            harvestedBal = harvestedBal.add(balanceOfWant()).sub(before).sub(_amount.sub(wantBal));
            wantBal = balanceOfWant().sub(harvestedBal);
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

    function harvest() external virtual gasThrottle {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual gasThrottle {
        _harvest(callFeeRecipient);
    }


    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        if (chargedFees) {
            uint256 before = balanceOfWant();
            xLocker.increaseAmount(lockerID, harvestedBal);

            lastHarvest = block.timestamp;
            chargedFees = false;
            harvested = false;
            emit StratHarvest(msg.sender, harvestedBal, balanceOf());
            harvestedBal = harvestedBal.add(balanceOfWant()).sub(before);
        } else {
            if (harvested) {
                if (harvestedBal > 0) {
                chargeFees(callFeeRecipient);
                }
            } else {
                uint256 before = balanceOfWant();
                rewardPool.harvestLock(lockerID);
                harvestedBal = harvestedBal.add(balanceOfWant()).sub(before);
                harvested = true;
            }
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 toNative = harvestedBal.mul(45).div(1000);
        harvestedBal = harvestedBal.sub(toNative);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
        chargedFees = true;
        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFee);

    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool()).sub(harvestedBal);
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return xLocker.stakedBalance(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return rewardPool.pendingRewardsOfLock(lockerID);
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

    function outputToNative() public view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        xLocker.withdraw(lockerID, address(this));

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        xLocker.withdraw(lockerID, address(this));
        lockerID = 0;
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
        IERC20(want).safeApprove(address(xLocker), uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(address(xLocker), 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4){
    return IERC721Receiver.onERC721Received.selector;
  }
}
