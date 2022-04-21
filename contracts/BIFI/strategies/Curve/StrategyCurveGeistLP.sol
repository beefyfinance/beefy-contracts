// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "../../utils/GasThrottler.sol";

contract StrategyCurveGeistLP is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public want; // curve lpToken
    address public crv;
    address public geist;
    address public native;
    address public depositToken;

    // Third party contracts
    address public rewardsGauge;
    address public pool;
    uint public immutable poolSize;
    uint public depositIndex;
    bool public useUnderlying;

    // Routes
    address[] public crvToNativeRoute;
    address[] public geistToNativeRoute;
    address[] public nativeToDepositRoute;

    // if no CRV rewards yet, can enable later with custom router
    bool public crvEnabled = true;
    address public crvRouter;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _want,
        address _gauge,
        address _pool,
        uint _poolSize,
        uint _depositIndex,
        bool _useUnderlying,
        address[] memory _crvToNativeRoute,
        address[] memory _geistToNativeRoute,
        address[] memory _nativeToDepositRoute,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        rewardsGauge = _gauge;
        pool = _pool;
        poolSize = _poolSize;
        depositIndex = _depositIndex;
        useUnderlying = _useUnderlying;

        crv = _crvToNativeRoute[0];
        native = _crvToNativeRoute[_crvToNativeRoute.length - 1];
        crvToNativeRoute = _crvToNativeRoute;
        crvRouter = unirouter;

        require(_geistToNativeRoute[_geistToNativeRoute.length - 1] == native, '_geistToNativeRoute[last] != native');
        geist = _geistToNativeRoute[0];
        geistToNativeRoute = _geistToNativeRoute;

        require(_nativeToDepositRoute[0] == native, '_nativeToDepositRoute[0] != native');
        depositToken = _nativeToDepositRoute[_nativeToDepositRoute.length - 1];
        nativeToDepositRoute = _nativeToDepositRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardsGauge(rewardsGauge).deposit(wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IRewardsGauge(rewardsGauge).withdraw(_amount.sub(wantBal));
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

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function harvest() external virtual whenNotPaused gasThrottle {
        _harvest();
    }

    function managerHarvest() external onlyManager {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal {
        IRewardsGauge(rewardsGauge).claim_rewards(address(this));
        uint256 crvBal = IERC20(crv).balanceOf(address(this));
        uint256 geistBal = IERC20(geist).balanceOf(address(this));
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0 || crvBal > 0 || geistBal > 0) {
            chargeFees();
            addLiquidity();
            deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender);
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 crvBal = IERC20(crv).balanceOf(address(this));
        if (crvEnabled && crvBal > 0) {
            IUniswapRouterETH(crvRouter).swapExactTokensForTokens(crvBal, 0, crvToNativeRoute, address(this), block.timestamp);
        }
        uint256 geistBal = IERC20(geist).balanceOf(address(this));
        if (geistBal > 0) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(geistBal, 0, geistToNativeRoute, address(this), block.timestamp);
        }

        uint256 nativeFeeBal = IERC20(native).balanceOf(address(this)).mul(45).div(1000);

        uint256 callFeeAmount = nativeFeeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = nativeFeeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeFeeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (depositToken != native) {
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeBal, 0, nativeToDepositRoute, address(this), block.timestamp);
        }

        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 4) {
            uint256[4] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 5) {
            uint256[5] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap(pool).add_liquidity(amounts, 0);
        }
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
        return IRewardsGauge(rewardsGauge).balanceOf(address(this));
    }

    function crvToNative() external view returns(address[] memory) {
        return crvToNativeRoute;
    }

    function geistToNative() external view returns(address[] memory) {
        return geistToNativeRoute;
    }

    function nativeToDeposit() external view returns(address[] memory) {
        return nativeToDepositRoute;
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

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IRewardsGauge(rewardsGauge).claimable_reward(address(this), crv);
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256[] memory amountOut = IUniswapRouterETH(unirouter).getAmountsOut(outputBal, crvToNativeRoute);
        uint256 nativeOut = amountOut[amountOut.length -1];

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
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
        IERC20(geist).safeApprove(unirouter, type(uint).max);
        IERC20(crv).safeApprove(crvRouter, type(uint).max);
        IERC20(depositToken).safeApprove(pool, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(geist).safeApprove(unirouter, 0);
        IERC20(crv).safeApprove(crvRouter, 0);
        IERC20(depositToken).safeApprove(pool, 0);
    }
}
