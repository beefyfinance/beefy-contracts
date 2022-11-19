// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
//pragma experimental ABIEncoderV2;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/stellaswap/IMasterChefV8.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/GasFeeThrottler.sol";

/**
 * Used to compound StellaDistributorV2
 */
contract StrategyStellaswapMultiRewardsLP is StratFeeManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
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
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;
    address[][] public rewardToNativeRoute;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        CommonAddresses memory _commonAddresses,
        address[] memory _outputToNativeRoute,
        address[] memory _nativeToLp0Route,
        address[] memory _nativeToLp1Route
    ) StratFeeManager(_commonAddresses) {
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
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChefV8(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChefV8(chef).withdraw(poolId, _amount - wantBal);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
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
    function _harvest(address callFeeRecipient) internal whenNotPaused{
        IMasterChefV8(chef).deposit(poolId, 0);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            _convertRewards();
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // converts rewards to native
    function _convertRewards() internal {
        // unwrap any native
        uint256 nativeBal = address(this).balance;
        if (nativeBal > 0) {
            IWrappedNative(native).deposit{value: nativeBal}();
        }
        // convert any output to native
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToNativeRoute, address(this), block.timestamp);

        // convert additional rewards
        if (rewardToNativeRoute.length != 0) {
            for (uint i; i < rewardToNativeRoute.length; i++) {
                uint256 toNative = IERC20(rewardToNativeRoute[i][0]).balanceOf(address(this));
                if (toNative > 0) {
                    IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, rewardToNativeRoute[i], address(this), block.timestamp);
                }
            }
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeFeesOwed = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeFeesOwed * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeFeesOwed * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeFeesOwed * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)) / 2;

        if (lpToken0 != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp0Route, address(this), block.timestamp);
        }

        if (lpToken1 != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeHalf, 0, nativeToLp1Route, address(this), block.timestamp);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouterETH(unirouter).addLiquidity(lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount,,,) = IMasterChefV8(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function rewardsAvailable() public view returns (address[] memory, uint256[] memory) {
        (address[] memory addresses,,,uint256[] memory amounts) = IMasterChefV8(chef).pendingTokens(poolId, address(this));
        return (addresses, amounts);
    }

    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        (address[] memory rewardAdd, uint256[] memory rewardBal) = rewardsAvailable();
        uint256 nativeOut;
        try IUniswapRouterETH(unirouter).getAmountsOut(rewardBal[0], outputToNativeRoute)
        returns (uint256[] memory amountOut) {
            nativeOut = amountOut[amountOut.length - 1];
        } catch {}

        if (rewardToNativeRoute.length != 0) {
            for (uint i; i < rewardToNativeRoute.length; i++) {
                for (uint j = 1; j < rewardAdd.length; j++) {
                    if (rewardAdd[j] == rewardToNativeRoute[i][0]) {
                        try IUniswapRouterETH(unirouter).getAmountsOut(rewardBal[j], rewardToNativeRoute[i])
                        returns (uint256[] memory amountOut) {
                           nativeOut = nativeOut + amountOut[amountOut.length - 1];
                        } catch {}
                    }
                }
            }
        }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
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

        IMasterChefV8(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMasterChefV8(chef).emergencyWithdraw(poolId);
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
        IERC20(want).safeApprove(chef, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint).max);

        if (rewardToNativeRoute.length != 0) {
            for (uint i; i < rewardToNativeRoute.length; i++) {
                IERC20(rewardToNativeRoute[i][0]).safeApprove(unirouter, 0);
                IERC20(rewardToNativeRoute[i][0]).safeApprove(unirouter, type(uint).max);
            }
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);

        if (rewardToNativeRoute.length != 0) {
            for (uint i; i < rewardToNativeRoute.length; i++) {
                IERC20(rewardToNativeRoute[i][0]).safeApprove(unirouter, 0);
            }
        }
    }

    function addRewardRoute(address[] memory _rewardToNativeRoute) external onlyOwner {
        IERC20(_rewardToNativeRoute[0]).safeApprove(unirouter, 0);
        IERC20(_rewardToNativeRoute[0]).safeApprove(unirouter, type(uint).max);
        rewardToNativeRoute.push(_rewardToNativeRoute);
    }

    function removeLastRewardRoute() external onlyManager {
        address reward = rewardToNativeRoute[rewardToNativeRoute.length - 1][0];
        if (reward != lpToken0 && reward != lpToken1) {
            IERC20(reward).safeApprove(unirouter, 0);
        }
        rewardToNativeRoute.pop();
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return nativeToLp0Route;
    }

    function nativeToLp1() external view returns (address[] memory) {
        return nativeToLp1Route;
    }

    function rewardToNative() external view returns (address[][] memory) {
        return rewardToNativeRoute;
    }

    receive () external payable {}
}