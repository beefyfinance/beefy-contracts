// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/ICommonMiniChef.sol";
import "../../interfaces/common/ICommonRewarderV8.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/GasFeeThrottler.sol";

contract StrategyCommonMinichefLP is StratFeeManagerInitializable, GasFeeThrottler {
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

    struct Reward {
        address token;
        address[] rewardToNativeRoute;
        uint256 minAmount;
    }

    Reward[] public rewards;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // Routes
    address[] public outputToNativeRoute;
    address[] public nativeToLp0Route;
    address[] public nativeToLp1Route;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        uint256 _poolId,
        address _chef,
        CommonAddresses calldata _commonAddresses,
        address[] memory _outputToNativeRoute,
        address[] memory _nativeToLp0Route,
        address[] memory _nativeToLp1Route
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        poolId = _poolId;
        chef = _chef;

        // set up output routing
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
        require(_nativeToLp1Route[_nativeToLp1Route.length - 1] == lpToken1, "nativeToLp01oute[last] != lpToken1");
        nativeToLp1Route = _nativeToLp1Route;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            ICommonMiniChef(chef).deposit(poolId, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ICommonMiniChef(chef).withdraw(poolId, _amount - wantBal, address(this));
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
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        ICommonMiniChef(chef).harvest(poolId, address(this));
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // swap rewards and output to native
    function swapRewardsToNative() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToNativeRoute, address(this), block.timestamp);
        }
        // extras
        for (uint256 i; i < rewards.length;) {
            uint256 bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                IUniswapRouterETH(unirouter).swapExactTokensForTokens(bal, 0, rewards[i].rewardToNativeRoute, address(this), block.timestamp);
            }
            unchecked{ i++;}
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
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
        (uint256 _amount, ) = ICommonMiniChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ICommonMiniChef(chef).emergencyWithdraw(poolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // returns secondary rewards unharvested
    function rewardsAvailable() public view returns (uint256, uint256[] memory) {
        uint256 outputReward = ICommonMiniChef(chef).pendingReward(poolId, address(this));
        uint256[] memory secondaryRewards;
        // checks if there is a rewarder associated with the pool, if not will return an empty array.
        address rewarder = ICommonMiniChef(chef).rewarder(poolId);
        if (rewarder != address(0)) {
        (, uint256[] memory amounts) = ICommonRewarderV8(rewarder).pendingTokens(poolId, address(this), outputReward);
            secondaryRewards = amounts;
        }

        return (outputReward, secondaryRewards);
    }

    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        (uint256 outputReward, uint256[] memory secondaryRewards) = rewardsAvailable();
        uint256 nativeBal;

        if (outputReward > 0) {
            nativeBal += estimateNativeValue(outputReward, outputToNativeRoute);
        } 

        for (uint256 i; i < rewards.length;) {
            nativeBal += estimateNativeValue(secondaryRewards[i], rewards[i].rewardToNativeRoute);
            unchecked{ i++; }
        }

        return nativeBal * fees.total / DIVISOR * fees.call / DIVISOR; 
    }

    function estimateNativeValue(uint256 _amountIn, address[] memory _route) internal view returns (uint256 reward) {
        uint256 _amountOut;
        try IUniswapRouterETH(unirouter).getAmountsOut(_amountIn, _route) 
            returns (uint256[] memory _amountsOut)
        {
            _amountOut = _amountsOut[_amountsOut.length - 1];
        } catch {}
        return _amountOut;
    }

    function addRewardToken(address _token, address[] calldata _rewardToNativeRoute, uint256 minAmount) external onlyOwner {
        require(_token != want, "!want");
        require(_token != native, "!native");
        require(_rewardToNativeRoute.length > 0, "!rewardToNativeRoute");
        require(_rewardToNativeRoute[0] == _token, "_rewardToNativeRoute[0] != _token");
        require(_rewardToNativeRoute[_rewardToNativeRoute.length - 1] == native, "_rewardToNativeRoute[last] != native");
    
        IERC20(_token).safeApprove(unirouter, 0);
        IERC20(_token).safeApprove(unirouter, type(uint).max);

        rewards.push(Reward(_token, _rewardToNativeRoute, minAmount));
    }

    function resetRewardTokens() external onlyManager {
        delete rewards;
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

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ICommonMiniChef(chef).emergencyWithdraw(poolId, address(this));
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

        if (rewards.length != 0) {
            for (uint256 i; i < rewards.length;) {
                IERC20(rewards[i].token).safeApprove(unirouter, 0);
                IERC20(rewards[i].token).safeApprove(unirouter, type(uint).max);
                unchecked{ i++; }
            }
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);

        if (rewards.length != 0) {
            for (uint256 i; i < rewards.length;) {
                IERC20(rewards[i].token).safeApprove(unirouter, 0);
                unchecked{ i++; }
            }
        }
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
    
    function reward0ToNative() external view returns (address[] memory) {
        return rewards[0].rewardToNativeRoute;
    }

    function reward1ToNative() external view returns (address[] memory) {
        return rewards[1].rewardToNativeRoute;
    }
}