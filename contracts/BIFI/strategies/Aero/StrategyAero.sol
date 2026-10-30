// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {
    SafeERC20Upgradeable as SafeERC20
} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable as Math} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "../../interfaces/aero/IAeroRouter.sol";
import "../../interfaces/aero/IAeroPair.sol";
import "../../interfaces/aero/IAeroGauge.sol";
import "../../interfaces/aero/IAeroFactoryRegistry.sol";
import "../../interfaces/aero/IAeroGaugeFactory.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../Common/StratFeeManagerInitializable.sol";

/// @notice Compounds Aero V2 gauge emissions into the staked LP token.
contract StrategyAero is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    bytes32 private constant V2_STABLE = bytes32("V2_STABLE");
    bytes32 private constant V2_VOLATILE = bytes32("V2_VOLATILE");

    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;
    address public gauge;
    address public factory;
    address public aeroRouter;

    bool public stable;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    error UnsupportedPoolType(bytes32 poolType);
    error InvalidInput();
    error InvalidLiquidity();
    error ActionLocked(uint256 unlockBlock);

    /// @param _output Gauge emission token, validated against the Metarouter.
    /// @param _aeroRouter Aero Metarouter used only for adding liquidity.
    /// @param _commonAddresses The common unirouter is the Beefy Swapper.
    function initialize(
        address _want,
        address _gauge,
        address _output,
        address _native,
        address _aeroRouter,
        bool _harvestOnDeposit,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        if (
            _want == address(0) || _gauge == address(0) || _output == address(0) || _native == address(0)
                || _aeroRouter == address(0) || _commonAddresses.unirouter == address(0)
                || _commonAddresses.vault == address(0) || _output == _want || _native == _want
        ) revert InvalidInput();
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        gauge = _gauge;
        output = _output;
        native = _native;
        aeroRouter = _aeroRouter;

        bytes32 poolType = IAeroPair(want).POOL_TYPE();
        if (poolType != V2_STABLE && poolType != V2_VOLATILE) revert UnsupportedPoolType(poolType);
        stable = poolType == V2_STABLE;
        factory = IAeroPair(want).factory();
        lpToken0 = IAeroPair(want).token0();
        lpToken1 = IAeroPair(want).token1();

        IAeroRouter router = IAeroRouter(payable(aeroRouter));
        if (
            !IAeroGauge(gauge).isPool() || IAeroGauge(gauge).stakingToken() != want
                || IAeroGauge(gauge).voter() != router.LEAF_VOTER() || output != router.EMISSION_TOKEN()
                || IAeroFactoryRegistry(router.FACTORY_REGISTRY()).targetToGauge(want) != gauge
        ) revert InvalidInput();

        setHarvestOnDeposit(_harvestOnDeposit);
    }

    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            _enforceActionDelay();
            IERC20(want).forceApprove(gauge, wantBal);
            IAeroGauge(gauge).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");
        uint256 wantBal = balanceOfWant();
        if (wantBal < _amount) {
            _enforceActionDelay();
            // Direct withdrawals also claim emissions to this strategy. The next
            // harvest processes the full output balance, including these claims.
            IAeroGauge(gauge).withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }
        if (wantBal > _amount) wantBal = _amount;
        if (tx.origin != owner() && !paused()) wantBal -= wantBal * withdrawalFee / WITHDRAWAL_MAX;
        IERC20(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            // The vault calls deposit() after minting shares and transferring
            // new LP. Restaking here would lock that second call in this block.
            _harvest(tx.origin, false);
        }
    }

    function harvest() external {
        _harvest(tx.origin, true);
    }

    function harvest(address callFeeRecipient) external {
        _harvest(callFeeRecipient, true);
    }

    function _harvest(address callFeeRecipient, bool _stake) internal whenNotPaused {
        _enforceActionDelay();
        IAeroGauge(gauge).claimEmissions(address(this), address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal == 0) return;

        // Convert emissions once to native, then fund both LP sides from the
        // proceeds. This only needs output -> native and native -> LP routes.
        uint256 nativeEarned = _swap(output, native, outputBal);
        uint256 remaining = _chargeFees(callFeeRecipient, nativeEarned);
        uint256 wantBefore = balanceOfWant();
        _addLiquidity(remaining);
        uint256 wantHarvested = balanceOfWant() - wantBefore;
        if (_stake) deposit();

        lastHarvest = block.timestamp;
        emit StratHarvest(msg.sender, wantHarvested, balanceOf());
    }

    /// @dev Charge only the native proceeds of this harvest, preserving any
    ///      native tokens already held as an LP constituent.
    function _chargeFees(address _recipient, uint256 _amount) internal returns (uint256 remaining) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 feeAmount = Math.mulDiv(_amount, fees.total, DIVISOR);
        remaining = _amount - feeAmount;
        uint256 callFees = feeAmount * fees.call / DIVISOR;
        uint256 strategistFees = feeAmount * fees.strategist / DIVISOR;
        uint256 beefyFees = feeAmount - callFees - strategistFees;
        IERC20(native).safeTransfer(_recipient, callFees);
        IERC20(native).safeTransfer(strategist, strategistFees);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFees);
        emit ChargedFees(callFees, beefyFees, strategistFees);
    }

    function _swap(address _from, address _to, uint256 _amount) internal returns (uint256) {
        if (_amount == 0 || _from == _to) return _amount;
        IERC20(_from).forceApprove(unirouter, _amount);
        return IBeefySwapper(unirouter).swap(_from, _to, _amount);
    }

    function _quote(address _from, address _to, uint256 _amount) internal view returns (uint256) {
        return _amount == 0 || _from == _to ? _amount : IBeefySwapper(unirouter).getAmountOut(_from, _to, _amount);
    }

    /// @dev Stable pools must be funded at their raw reserve ratio, which need
    ///      not be equal token values. Quote equal native inputs in raw units;
    ///      multiplying by the inverse reserve ratio cancels token decimals.
    function _liquiditySplit(uint256 _amount) internal view returns (uint256 amount0, uint256 amount1) {
        amount0 = _amount / 2;
        if (stable && amount0 > 0) {
            (uint256 reserve0, uint256 reserve1,) = IAeroPair(want).getReserves();
            uint256 quote0 = _quote(native, lpToken0, amount0);
            uint256 quote1 = _quote(native, lpToken1, amount0);
            if (reserve0 == 0 || reserve1 == 0 || quote0 == 0 || quote1 == 0) revert InvalidLiquidity();
            uint256 ratio = Math.mulDiv(quote0, DIVISOR, quote1);
            ratio = Math.mulDiv(ratio, reserve1, reserve0);
            amount0 = Math.mulDiv(_amount, DIVISOR, DIVISOR + ratio);
        }
        amount1 = _amount - amount0;
    }

    function _addLiquidity(uint256 _amount) internal {
        (uint256 amount0, uint256 amount1) = _liquiditySplit(_amount);
        _swap(native, lpToken0, amount0);
        _swap(native, lpToken1, amount1);

        uint256 balance0 = IERC20(lpToken0).balanceOf(address(this));
        uint256 balance1 = IERC20(lpToken1).balanceOf(address(this));
        if (balance0 == 0 || balance1 == 0) return;

        IERC20(lpToken0).forceApprove(aeroRouter, balance0);
        IERC20(lpToken1).forceApprove(aeroRouter, balance1);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            IAeroRouter.AddLiquidityParams({
                factory: factory,
                tokenA: lpToken0,
                tokenB: lpToken1,
                createPool: false,
                spendA: IAeroRouter.BalanceSpend(IAeroRouter.SpendMode.Amount, balance0),
                spendB: IAeroRouter.BalanceSpend(IAeroRouter.SpendMode.Amount, balance1),
                payerAIsUser: true,
                payerBIsUser: true,
                amountAMin: 1,
                amountBMin: 1,
                recipient: address(this),
                liquidityMin: 1
            })
        );
        IAeroRouter(payable(aeroRouter)).execute(hex"22", inputs, block.timestamp);
        // The Metarouter may trim the funded amounts. Clear any unspent approval.
        IERC20(lpToken0).forceApprove(aeroRouter, 0);
        IERC20(lpToken1).forceApprove(aeroRouter, 0);
    }

    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfPool() public view returns (uint256) {
        return IAeroGauge(gauge).balanceOf(address(this));
    }

    function rewardsAvailable() public view returns (uint256) {
        return IAeroGauge(gauge).earned(address(this)) + IERC20(output).balanceOf(address(this));
    }

    function callReward() public view returns (uint256) {
        if (block.number < actionableBlock()) return 0;
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeOut = _quote(output, native, rewardsAvailable());
        uint256 feeAmount = Math.mulDiv(nativeOut, fees.total, DIVISOR);
        return feeAmount * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        setWithdrawalFee(_harvestOnDeposit ? 0 : 10);
    }

    function lastGaugeDepositBlock() public view returns (uint256) {
        return IAeroGauge(gauge).depositBlock(address(this));
    }

    function minStakeBlocks() public view returns (uint256) {
        IAeroGaugeFactory.PenaltyConfig memory config =
            IAeroGaugeFactory(IAeroGauge(gauge).gaugeFactory()).effectivePenaltyConfig(gauge);
        return config.penaltyRate == 0 ? 0 : config.minStakeBlocks;
    }

    function actionableBlock() public view returns (uint256) {
        uint256 deposited = lastGaugeDepositBlock();
        return deposited == 0 ? 0 : deposited + minStakeBlocks();
    }

    function actionable() external view returns (bool) {
        return block.number >= actionableBlock();
    }

    function _enforceActionDelay() internal view {
        uint256 unlockBlock = actionableBlock();
        if (block.number < unlockBlock) revert ActionLocked(unlockBlock);
    }

    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _enforceActionDelay();
        uint256 staked = balanceOfPool();
        if (staked > 0) IAeroGauge(gauge).withdraw(staked);
        IERC20(want).safeTransfer(vault, balanceOfWant());
    }

    /// @notice Emergency exit, accepting any penalty on accrued emissions.
    function panic() external onlyManager {
        if (!paused()) _pause();
        uint256 staked = balanceOfPool();
        if (staked > 0) IAeroGauge(gauge).withdraw(staked);
    }

    function pause() external onlyManager {
        _pause();
    }

    function unpause() external onlyManager {
        _unpause();
        deposit();
    }
}
