// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../../interfaces/curve/IGaugeFactory.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/GasFeeThrottler.sol";

contract StrategyCurveLP is StratFeeManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want; // curve lpToken
    address public crv;
    address public native;
    address public depositToken;

    // Third party contracts
    address public gaugeFactory;
    address public rewardsGauge;
    address public pool;
    address public zap; // curve zap to deposit in metapools, or 0
    uint public poolSize;
    uint public depositIndex;
    bool public useUnderlying;

    // Routes
    address[] public crvToNativeRoute;
    address[] public nativeToDepositRoute;

    struct Reward {
        address token;
        address[] toNativeRoute;
        uint minAmount; // minimum amount to be swapped to native
    }

    Reward[] public rewards;

    // if no CRV rewards yet, can enable later with custom router
    bool public crvEnabled = true;
    address public crvRouter;

    // if depositToken should be sent as unwrapped native
    bool public depositNative;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        address _gaugeFactory,
        address _gauge,
        address _pool,
        address _zap,
        uint[] memory _params, // [poolSize, depositIndex, useUnderlying, useDepositNative]
        address[] memory _crvToNativeRoute,
        address[] memory _nativeToDepositRoute,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        want = _want;
        gaugeFactory = _gaugeFactory;
        rewardsGauge = _gauge;
        pool = _pool;
        zap = _zap;
        poolSize = _params[0];
        depositIndex = _params[1];
        useUnderlying = _params[2] > 0;
        depositNative = _params[3] > 0;

        crv = _crvToNativeRoute[0];
        native = _crvToNativeRoute[_crvToNativeRoute.length - 1];
        crvToNativeRoute = _crvToNativeRoute;
        crvRouter = unirouter;

        require(_nativeToDepositRoute[0] == native, '_nativeToDepositRoute[0] != native');
        depositToken = _nativeToDepositRoute[_nativeToDepositRoute.length - 1];
        nativeToDepositRoute = _nativeToDepositRoute;

        if (gaugeFactory != address(0)) {
            harvestOnDeposit = true;
            withdrawalFee = 0;
        }

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardsGauge(rewardsGauge).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IRewardsGauge(rewardsGauge).withdraw(_amount - wantBal);
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

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        if (gaugeFactory != address(0)) {
            IGaugeFactory(gaugeFactory).mint(rewardsGauge);
        }
        IRewardsGauge(rewardsGauge).claim_rewards(address(this));
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

    function swapRewardsToNative() internal {
        uint256 crvBal = IERC20(crv).balanceOf(address(this));
        if (crvEnabled && crvBal > 0) {
            IUniswapRouterETH(crvRouter).swapExactTokensForTokens(crvBal, 0, crvToNativeRoute, address(this), block.timestamp);
        }
        // extras
        for (uint i; i < rewards.length; i++) {
            uint bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                IUniswapRouterETH(unirouter).swapExactTokensForTokens(bal, 0, rewards[i].toNativeRoute, address(this), block.timestamp);
            }
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
        uint256 depositBal;
        uint256 depositNativeAmount;
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (depositToken != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeBal, 0, nativeToDepositRoute, address(this), block.timestamp);
            depositBal = IERC20(depositToken).balanceOf(address(this));
        } else {
            depositBal = nativeBal;
            if (depositNative) {
                depositNativeAmount = nativeBal;
                IWrappedNative(native).withdraw(depositNativeAmount);
            }
        }

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else ICurveSwap(pool).add_liquidity{value: depositNativeAmount}(amounts, 0);
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else if (zap != address(0)) ICurveSwap(zap).add_liquidity{value: depositNativeAmount}(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity{value: depositNativeAmount}(amounts, 0);
        } else if (poolSize == 4) {
            uint256[4] memory amounts;
            amounts[depositIndex] = depositBal;
            if (zap != address(0)) ICurveSwap(zap).add_liquidity(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 5) {
            uint256[5] memory amounts;
            amounts[depositIndex] = depositBal;
            if (zap != address(0)) ICurveSwap(zap).add_liquidity(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 6) {
            uint256[6] memory amounts;
            amounts[depositIndex] = depositBal;
            if (zap != address(0)) ICurveSwap(zap).add_liquidity(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        }
    }

    function addRewardToken(address[] memory _rewardToNativeRoute, uint _minAmount) external onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != rewardsGauge, "!native");

        rewards.push(Reward(token, _rewardToNativeRoute, _minAmount));
        IERC20(token).safeApprove(unirouter, 0);
        IERC20(token).safeApprove(unirouter, type(uint).max);
    }

    function resetRewardTokens() external onlyManager {
        delete rewards;
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
        return IRewardsGauge(rewardsGauge).balanceOf(address(this));
    }

    function crvToNative() external view returns (address[] memory) {
        return crvToNativeRoute;
    }

    function nativeToDeposit() external view returns (address[] memory) {
        return nativeToDepositRoute;
    }

    function rewardToNative() external view returns (address[] memory) {
        return rewards[0].toNativeRoute;
    }

    function rewardToNative(uint i) external view returns (address[] memory) {
        return rewards[i].toNativeRoute;
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function setCrvEnabled(bool _enabled) external onlyManager {
        crvEnabled = _enabled;
    }

    function setCrvRoute(address _router, address[] memory _crvToNative) external onlyManager {
        require(_crvToNative[0] == crv, '!crv');
        require(_crvToNative[_crvToNative.length - 1] == native, '!native');

        _removeAllowances();
        crvToNativeRoute = _crvToNative;
        crvRouter = _router;
        _giveAllowances();
    }

    function setDepositNative(bool _depositNative) external onlyOwner {
        depositNative = _depositNative;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IRewardsGauge(rewardsGauge).claimable_reward(address(this), crv);
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256[] memory amountOut = IUniswapRouterETH(unirouter).getAmountsOut(outputBal, crvToNativeRoute);
        uint256 nativeOut = amountOut[amountOut.length - 1];

        IFeeConfig.FeeCategory memory fees = getFees();
        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());
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
        IERC20(want).safeApprove(rewardsGauge, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        IERC20(crv).safeApprove(crvRouter, type(uint).max);
        IERC20(depositToken).safeApprove(pool, type(uint).max);
        if (zap != address(0)) IERC20(depositToken).approve(zap, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(crv).safeApprove(crvRouter, 0);
        IERC20(depositToken).safeApprove(pool, 0);
        if (zap != address(0)) IERC20(depositToken).approve(zap, 0);
    }

    receive () external payable {}
}
