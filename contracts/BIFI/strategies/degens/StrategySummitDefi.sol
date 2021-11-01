// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IERC20Extended.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/GasThrottler.sol";

interface ISummitCartographer {
    function deposit(uint16 _pid, uint256 _amount, uint256 _expedSummitLpAmount, uint8 _totem) external;
    function withdraw(uint16 _pid, uint256 _amount, uint256 _expedSummitLpAmount) external;
    function rewards(uint16 _pid, address _userAdd) external view returns (uint256, uint256, uint256, uint256);
}

interface ISummitCartographerOasis {
    function userInfo(uint16 _pid, address _user) external view returns (uint256 debt, uint256 staked);
}

interface ISummitReferrals {
    function createReferral(address referrerAddress) external;
    function getPendingReferralRewards(address user) external view returns (uint256);
    function redeemReferralRewards() external;
}

contract StrategySummitDefi is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address constant nullAddress = address(0);

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public cartographer;
    ISummitCartographerOasis public cartographerOasis;
    ISummitReferrals public referrals;
    uint16 public poolId;
    uint8 public constant totem = 0;
    bool referralsEnabled = true;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToWantRoute; // if want is not LP
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;

    bool public harvestOnDeposit = true;
    uint256 public lastHarvest;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _want,
        uint16 _poolId,
        address _cartographer,
        address _cartographerOasis,
        address _referrals,
        address _referrer,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        poolId = _poolId;

        cartographer = _cartographer;
        cartographerOasis = ISummitCartographerOasis(_cartographerOasis);
        referrals = ISummitReferrals(_referrals);
        referrals.createReferral(_referrer);

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        if (_outputToWantRoute.length > 0) {
            require(_outputToWantRoute[0] == output, "outputToWantRoute[0] != output");
            require(_outputToWantRoute[_outputToWantRoute.length - 1] == want, "outputToWantRoute[last] != want");
            outputToWantRoute = _outputToWantRoute;
        } else {
            lpToken0 = IUniswapV2Pair(want).token0();
            require(_outputToLp0Route[0] == output, "outputToLp0Route[0] != output");
            outputToLp0Route = _outputToLp0Route;

            lpToken1 = IUniswapV2Pair(want).token1();
            require(_outputToLp1Route[0] == output, "outputToLp1Route[0] != output");
            outputToLp1Route = _outputToLp1Route;
        }

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            ISummitCartographer(cartographer).deposit(poolId, wantBal, 0, totem);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            ISummitCartographer(cartographer).withdraw(poolId, _amount.sub(wantBal), 0);
            wantBal = balanceOfWant();
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
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
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
        ISummitCartographer(cartographer).deposit(poolId, 0, 0, totem);
        claimReferrals();
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            swapRewards();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender);
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

    // Swaps rewards and adds liquidity if needed
    function swapRewards() internal {
        if (output == want) {
            // do nothing
        } else if (outputToWantRoute.length > 1) {
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantRoute, address(this), now);
        } else {
            addLiquidity();
        }
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputHalf = IERC20(output).balanceOf(address(this)).div(2);

        if (lpToken0 != output) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputHalf, 0, outputToLp0Route, address(this), now);
        }

        if (lpToken1 != output) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputHalf, 0, outputToLp1Route, address(this), now);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouterETH(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), now);
    }

    function claimReferrals() public {
        if (referralsEnabled && referrals.getPendingReferralRewards(address(this)) > 0) {
            referrals.redeemReferralRewards();
        }
    }

    function setReferralsEnabled(bool _enabled) external onlyManager {
        referralsEnabled = _enabled;
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
        (,uint256 staked) = cartographerOasis.userInfo(poolId, address(this));
        return staked;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        (uint256 rewards,,,) = ISummitCartographer(cartographer).rewards(poolId, address(this));
        return rewards;
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

    function outputToLp0() public view returns (address[] memory) {
        return outputToLp0Route;
    }

    function outputToLp1() public view returns (address[] memory) {
        return outputToLp1Route;
    }

    function outputToNative() public view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToWant() public view returns (address[] memory) {
        return outputToWantRoute;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit == true) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ISummitCartographer(cartographer).withdraw(poolId, balanceOfPool(), 0);

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ISummitCartographer(cartographer).withdraw(poolId, balanceOfPool(), 0);
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
        IERC20(want).safeApprove(cartographer, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));

        if (lpToken0 != nullAddress) {
            IERC20(lpToken0).safeApprove(unirouter, 0);
            IERC20(lpToken0).safeApprove(unirouter, uint256(-1));

            IERC20(lpToken1).safeApprove(unirouter, 0);
            IERC20(lpToken1).safeApprove(unirouter, uint256(-1));
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(cartographer, 0);
        IERC20(output).safeApprove(unirouter, 0);
        if (lpToken0 != nullAddress) {
            IERC20(lpToken0).safeApprove(unirouter, 0);
            IERC20(lpToken1).safeApprove(unirouter, 0);
        }
    }
}
