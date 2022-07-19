// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/kyber/IKyberElasticSwap.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/kyber/IElysianFields.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../../interfaces/kyber/IJarvisMinter.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyJarvis is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct JarvisContracts {
        address synth;
        address minter;
    }

    struct StratManagerParams {
        address keeper;
        address strategist;
        address unirouter;
        address vault;
        address beefyFeeRecipient;
    }

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public stable;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    JarvisContracts public jarvis;
    uint256 public depositIndex;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // Routes
    address public outputToStablePool;
    uint160 constant public MAX_LIMIT = 1461446703485210103287273052203988822378723970341;
    address[] public stableToNativeRoute;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        uint256 _depositIndex,
        JarvisContracts memory _jarvis,
        StratManagerParams memory _stratManager,
        address _outputToStablePool,
        address[] memory _stableToNativeRoute
    ) StratManager(_stratManager.keeper, _stratManager.strategist, _stratManager.unirouter, _stratManager.vault, _stratManager.beefyFeeRecipient) public {
        want = _want;
        poolId = _poolId;
        chef = _chef;
        depositIndex = _depositIndex;
        jarvis = _jarvis;

        output = IElysianFields(_chef).rwdToken();
        outputToStablePool = _outputToStablePool;

        stable = _stableToNativeRoute[0];
        native = _stableToNativeRoute[_stableToNativeRoute.length - 1];

        stableToNativeRoute = _stableToNativeRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IElysianFields(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IElysianFields(chef).withdraw(poolId, _amount.sub(wantBal));
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

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IElysianFields(chef).deposit(poolId, 0);
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
        uint256 toStable = IERC20(output).balanceOf(address(this));
        IKyberElasticSwap(outputToStablePool).swap(address(this), int256(toStable), false, MAX_LIMIT, "");

        uint256 toNative = IERC20(stable).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, stableToNativeRoute, address(this), now);

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
        uint256 stableBal = IERC20(stable).balanceOf(address(this));
        IJarvisMinter.MintParams memory mintParams =
            IJarvisMinter.MintParams(
                1,
                stableBal,
                now,
                address(this)
            );
        IJarvisMinter(jarvis.minter).mint(mintParams);

        uint256 depositBal = IERC20(jarvis.synth).balanceOf(address(this));
        uint256[2] memory amounts;
        amounts[depositIndex] = depositBal;
        ICurveSwap(want).add_liquidity(amounts, 1);
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
        (uint256 _amount,) = IElysianFields(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IElysianFields(chef).pendingRwd(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();

        (uint160 sqrtP,,,) = IKyberElasticSwap(outputToStablePool).getPoolState();
        uint256 price = uint256(sqrtP).mul(uint256(sqrtP)).mul(1e18) >> 96;
        uint256 stableOut = outputBal.mul(1e18).div(price);

        uint256[] memory amountOutFromStable = IUniswapRouterETH(unirouter).getAmountsOut(stableOut, stableToNativeRoute);
        uint256 nativeOut = amountOutFromStable[amountOutFromStable.length -1];

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

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IElysianFields(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IElysianFields(chef).emergencyWithdraw(poolId);
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
        IERC20(output).safeApprove(outputToStablePool, uint256(-1));
        IERC20(stable).safeApprove(unirouter, uint256(-1));
        IERC20(stable).safeApprove(jarvis.minter, uint256(-1));
        IERC20(jarvis.synth).safeApprove(want, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(outputToStablePool, 0);
        IERC20(stable).safeApprove(unirouter, 0);
        IERC20(stable).safeApprove(jarvis.minter, 0);
        IERC20(jarvis.synth).safeApprove(want, 0);
    }

    function stableToNative() external view returns (address[] memory) {
        return stableToNativeRoute;
    }
}