// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMasterChef.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/GasFeeThrottler.sol";
import "../../utils/StringUtils.sol";
import "../../interfaces/beefy/IBeefyVaultV8.sol";

contract StrategyBase is StratFeeManager, GasFeeThrottler {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;
    address[] public rewards;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    string public pendingRewardsFunctionName;
    uint256 public slippage = 0.98 ether;

    // Routes
    mapping(address => mapping(address => address[])) public routes;
    mapping(address => uint256) public minToSwap;

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
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route
    ) StratFeeManager(_commonAddresses) {
        want = _want;
        poolId = _poolId;
        chef = _chef;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        routes[output][native] = _outputToNativeRoute;

        // setup lp routing
        lpToken0 = IUniswapV2Pair(want).token0();
        require(_outputToLp0Route[0] == output, "outputToLp0Route[0] != output");
        require(
            _outputToLp0Route[_outputToLp0Route.length - 1] == lpToken0,
            "outputToLp0Route[last] != lpToken0"
        );
        routes[output][lpToken0] = _outputToLp0Route;

        lpToken1 = IUniswapV2Pair(want).token1();
        require(_outputToLp1Route[0] == output, "outputToLp1Route[0] != output");
        require(
            _outputToLp1Route[_outputToLp1Route.length - 1] == lpToken1,
            "outputToLp1Route[last] != lpToken1"
        );
        routes[output][lpToken1] = _outputToLp1Route;

        _giveAllowances();
    }

    /**
     * @dev Only called by the vault to withdraw a requested amount. Losses from liquidating the
     * requested funds are recorded and reported to the vault.
     * @param amount The amount of assets to withdraw.
     * @param loss The loss that occured when liquidating the assets.
     */
    function withdraw(uint256 amount) external virtual returns (uint256 loss) {
        require(msg.sender == vault);

        uint256 amountFreed;
        (amountFreed, loss) = _liquidatePosition(amount);
        IERC20Upgradeable(want).safeTransfer(vault, amountFreed);

        emit Withdraw(balanceOf());
    }

    /**
     * @dev External function for anyone to harvest this strategy, protected by a gas throttle to
     * prevent front-running. Call fee goes to the caller of this function.
     */
    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    /**
     * @dev External function for anyone to harvest this strategy, protected by a gas throttle to
     * prevent front-running. Call fee goes to the specified recipient.
     */
    function harvest(address callFeeRecipient) external gasThrottle virtual {
        _harvest(callFeeRecipient);
    }

    /**
     * @dev External function for the manager to harvest this strategy to be used in times of high gas
     * prices. Call fee goes to the caller of this function.
     */
    function managerHarvest() external onlyManager virtual {
        _harvest(tx.origin);
    }

    /**
     * @dev It calculates the total underlying balance of 'want' held by this strategy including
     * the invested amount.
     * @return totalBalance The total balance of the wanted asset.
     */
    function balanceOf() public virtual view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    /**
     * @dev It calculates the balance of 'want' held directly on this address.
     * @return balanceOfWant The balance of the wanted asset on this address.
     */
    function balanceOfWant() public virtual view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev It calculates the invested balance of 'want' in the underlying platform.
     * @return balanceOfPool The invested balance of the wanted asset.
     */
    function balanceOfPool() public virtual view returns (uint256) {
        (uint256 _amount,) = IMasterChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    /**
     * @dev It sets the name of the pending rewards function in the underlying platform so the
     * total amount of rewards can be fetched.
     * @param _pendingRewardsFunctionName The name of the pending rewards function.
     */
    function setPendingRewardsFunctionName(
        string calldata _pendingRewardsFunctionName
    ) external onlyManager virtual {
        pendingRewardsFunctionName = _pendingRewardsFunctionName;
    }

    /**
     * @dev It calculates the output reward available to the strategy by calling the pending
     * rewards function on the underlying platform.
     * @return rewardsAvailable The amount of output rewards not yet harvested.
     */
    function rewardsAvailable() public virtual view returns (uint256) {
        string memory signature = StringUtils.concat(pendingRewardsFunctionName, "(uint256,address)");
        bytes memory result = Address.functionStaticCall(
            chef,
            abi.encodeWithSignature(
                signature,
                poolId,
                address(this)
            )
        );
        return abi.decode(result, (uint256));
    }

    /**
     * @dev It calculates the native reward for a caller to harvest the strategy. Fees are fetched
     * from the Beefy Fee Configurator and applied.
     * @return callReward The native reward amount for a harvest caller.
     */
    function callReward() public virtual view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            nativeOut = _getAmountOut(unirouter, outputBal, output, native);
        }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    /**
     * @dev It turns on or off the gas throttle to limit the gas price on harvests.
     * @param _shouldGasThrottle Change the activation of the gas throttle.
     */
    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager virtual {
        shouldGasThrottle = _shouldGasThrottle;
    }

    /**
     * @dev It shuts down deposits, removes allowances and prepares the full withdrawal of funds
     * back to the vault on next harvest.
     */
    function pause() public onlyManager virtual {
        _pause();
        _removeAllowances();
        _revokeStrategy();
    }

    /**
     * @dev It reopens possible deposits and reinstates allowances. The debt ratio needs to be
     * updated on the vault and the next harvest will bring in funds from the vault.
     */
    function unpause() external onlyManager virtual {
        _unpause();
        _giveAllowances();
    }

    /**
     * @dev Helper function to view the token route for swapping between output and native.
     * @return outputToNativeRoute The token route between output to native.
     */
    function outputToNative() external virtual view returns (address[] memory) {
        return routes[output][native];
    }

    /**
     * @dev Helper function to view the token route for swapping between output and lpToken0.
     * @return outputToLp0Route The token route between output to lpToken0.
     */
    function outputToLp0() external virtual view returns (address[] memory) {
        return routes[output][lpToken0];
    }

    /**
     * @dev Helper function to view the token route for swapping between output and lpToken1.
     * @return outputToLp1Route The token route between output to lpToken1.
     */
    function outputToLp1() external virtual view returns (address[] memory) {
        return routes[output][lpToken1];
    }

    /**
     * @dev It sets a route for a swap.
     * @param route The token route.
     */
    function setRoute(address[] calldata route) external onlyOwner virtual {
        address fromToken = route[0];
        address toToken = route[route.length - 1];
        routes[fromToken][toToken] = route;
    }

    /* ----------- INTERNAL VIRTUAL ----------- */
    // To be overridden by child contracts

    /**
     * @dev Helper function to deposit to the underlying platform.
     * @param amount The amount to deposit.
     */
    function _depositUnderlying(uint256 amount) internal virtual {
        IMasterChef(chef).deposit(poolId, amount);
    }

    /**
     * @dev Helper function to withdraw from the underlying platform.
     * @param amount The amount to withdraw.
     */
    function _withdrawUnderlying(uint256 amount) internal virtual {
        IMasterChef(chef).withdraw(poolId, amount);
    }

    /**
     * @dev Internal function to harvest the strategy. If not paused then collect rewards, charge
     * fees and convert output to the want token. Exchange funds with the vault if the strategy is
     * owed more vault allocation or if the strategy has a debt to pay back to the vault.
     * @param callFeeRecipient The address to send the call fee to.
     */
    function _harvest(address callFeeRecipient) internal virtual {
        if (!paused()) {
            _getRewards();
            if (IERC20Upgradeable(output).balanceOf(address(this)) > 0) {
                _chargeFees(callFeeRecipient);
                _convertToWant();
            }
        }

        uint256 gain = _balanceVaultFunds();
        lastHarvest = block.timestamp;
        emit StratHarvest(msg.sender, gain, balanceOf());
    }

    /**
     * @dev Internal function to exchange funds with the vault.
     * Any debt to pay to the vault is liquidated from the underlying platform and sent to the
     * vault when reporting. The strategy also can collect more funds when reporting if it is in
     * credit. Funds left on this contract are reinvested when not paused, minus the outstanding
     * debt to the vault.
     * @return gain The increase in assets from this harvest.
     */
    function _balanceVaultFunds() internal virtual returns (uint256 gain) {
        (int256 roi, uint256 repayment) = _liquidateRepayment(_getDebt());
        gain = roi > 0 ? uint256(roi) : 0;

        uint256 outstandingDebt = IBeefyVaultV8(vault).report(roi, repayment);
        _adjustPosition(outstandingDebt);
    }

    /**
     * @dev It fetches the debt owed to the vault from this strategy.
     * @return debt The amount owed to the vault.
     */
    function _getDebt() internal virtual returns (uint256 debt) {
        int256 availableCapital = IBeefyVaultV8(vault).availableCapital(address(this));
        if (availableCapital < 0) {
            debt = uint256(-availableCapital);
        }
    }

    /**
     * @dev It calculates the return on investment and liquidates an amount to claimed by the vault.
     * @param debt The amount owed to the vault.
     * @return roi The return on investment from last harvest report.
     * @return repayment The amount liquidated to repay the debt to the vault.
     */
    function _liquidateRepayment(uint256 debt) internal virtual returns (
        int256 roi, 
        uint256 repayment
    ) {
        uint256 allocated = IBeefyVaultV8(vault).strategies(address(this)).allocated;
        uint256 totalAssets = balanceOf();
        uint256 toFree = debt;

        if (totalAssets > allocated) {
            uint256 profit = totalAssets - allocated;
            toFree += profit;
            roi = int256(profit);
        } else if (totalAssets < allocated) {
            roi = -int256(allocated - totalAssets);
        }

        (uint256 amountFreed, uint256 loss) = _liquidatePosition(toFree);
        repayment = MathUpgradeable.min(debt, amountFreed);
        roi -= int256(loss);
    }

    /**
     * @dev It liquidates the amount owed to the vault from the underlying platform to allow the
     * vault to claim the repayment amount when reporting.
     * @param amountNeeded The amount owed to the vault.
     * @return liquidatedAmount The return on investment from last harvest report.
     * @return loss The amount freed to repay the debt to the vault.
     */
    function _liquidatePosition(uint256 amountNeeded)
        internal
        virtual
        returns (uint256 liquidatedAmount, uint256 loss)
    {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < amountNeeded) {
            if (paused()) {
                _emergencyWithdraw();
            } else {
                _withdrawUnderlying(amountNeeded - wantBal);
            }
            liquidatedAmount = IERC20Upgradeable(want).balanceOf(address(this));
        } else {
            liquidatedAmount = amountNeeded;
        }
        
        if (amountNeeded > liquidatedAmount) {
            loss = amountNeeded - liquidatedAmount;
        }
    }

    /**
     * @dev It reinvests the amount of assets on this address minus the outstanding debt so it can
     * be claimed easily on next harvest.
     * @param debt The outstanding amount owed to the vault.
     */
    function _adjustPosition(uint256 debt) internal virtual {
        if (paused()) {
            return;
        }

        uint256 wantBalance = balanceOfWant();
        if (wantBalance > debt) {
            uint256 toReinvest = wantBalance - debt;
            _depositUnderlying(toReinvest);
        }
    }

    /**
     * @dev It claims rewards from the underlying platform and converts any extra rewards back into
     * the output token.
     */
    function _getRewards() internal virtual {
        IMasterChef(chef).deposit(poolId, 0);
        uint256 rewardLength = rewards.length;
        for (uint256 i; i < rewardLength;) {
            _swap(unirouter, rewards[i], output, 1 ether);
            unchecked { ++i; }
        }
    }

    /**
     * @dev It fetches fees and charges the appropriate amount on the output token. Fees are sent
     * to the various stored addresses and to the specified call fee recipient.
     * @param callFeeRecipient The address to send the call fee to.
     */
    function _chargeFees(address callFeeRecipient) internal virtual {
        IFeeConfig.FeeCategory memory fees = getFees();

        _swap(unirouter, output, native, fees.total);

        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    /**
     * @dev It converts the output to the want asset, in this case it swaps half for each LP token
     * and adds liquidity.
     */
    function _convertToWant() internal virtual {
        _swap(unirouter, output, lpToken0, 0.5 ether);
        _swap(unirouter, output, lpToken1, 0.5 ether);

        uint256 lp0Bal = IERC20Upgradeable(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20Upgradeable(lpToken1).balanceOf(address(this));
        IUniswapRouterETH(unirouter).addLiquidity(
            lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp
        );
    }

    /**
     * @dev It swaps from one token to another, taking into account the route and slippage.
     * @param _unirouter The router used to make the swap.
     * @param _fromToken The token to swap from.
     * @param _toToken The token to swap to.
     * @param _percentageSwap The percentage of the fromToken to use in the swap, scaled to 1e18.
     */
    function _swap(
        address _unirouter,
        address _fromToken,
        address _toToken,
        uint256 _percentageSwap
    ) internal virtual {
        if (_fromToken == _toToken) {
            return;
        }
        uint256 fromTokenBal = 
            IERC20Upgradeable(_fromToken).balanceOf(address(this)) * _percentageSwap / DIVISOR;
        if (fromTokenBal > minToSwap[_fromToken]) {
            address[] memory path = routes[_fromToken][_toToken];
            require(path[0] != address(0), "path not set");
            uint256 minOutput = _getAmountOut(_unirouter, fromTokenBal, _fromToken, _toToken)
                * slippage
                / DIVISOR;

            try IUniswapRouterETH(_unirouter).swapExactTokensForTokens(
                fromTokenBal, minOutput, path, address(this), block.timestamp
            ) {} catch {}
        }
    }

    /**
     * @dev It withdraws from the underlying platform without caring about rewards.
     */
    function _emergencyWithdraw() internal virtual {
        IMasterChef(chef).emergencyWithdraw(poolId);
    }

    /**
     * @dev It estimated the amount received from making a swap.
     * @param _unirouter The router used to make the swap.
     * @param _amountIn The amount of fromToken to be used in the swap.
     * @param _fromToken The token to swap from.
     * @param _toToken The token to swap to.
     */
    function _getAmountOut(
        address _unirouter,
        uint256 _amountIn,
        address _fromToken,
        address _toToken
    ) internal virtual view returns (uint256 amount) {
        uint256[] memory amountOut = IUniswapRouterETH(_unirouter).getAmountsOut(
            _amountIn,
            routes[_fromToken][_toToken]
        );
        amount = amountOut[amountOut.length - 1];
    }

    /**
     * @dev It gives allowances to the required addresses.
     */
    function _giveAllowances() internal virtual {
        IERC20Upgradeable(want).safeApprove(chef, type(uint).max);
        IERC20Upgradeable(output).safeApprove(unirouter, type(uint).max);

        IERC20Upgradeable(lpToken0).safeApprove(unirouter, 0);
        IERC20Upgradeable(lpToken0).safeApprove(unirouter, type(uint).max);

        IERC20Upgradeable(lpToken1).safeApprove(unirouter, 0);
        IERC20Upgradeable(lpToken1).safeApprove(unirouter, type(uint).max);
    }

    /**
     * @dev It revokes allowances from the previously approved addresses.
     */
    function _removeAllowances() internal virtual {
        IERC20Upgradeable(want).safeApprove(chef, 0);
        IERC20Upgradeable(output).safeApprove(unirouter, 0);
        IERC20Upgradeable(lpToken0).safeApprove(unirouter, 0);
        IERC20Upgradeable(lpToken1).safeApprove(unirouter, 0);
    }

    /**
     * @dev It revokes the strategy's debt ratio allocation on the vault, so that all of the funds
     * in this strategy will be sent to the vault on the next harvest.
     */
    function _revokeStrategy() internal virtual {
        IBeefyVaultV8(vault).revokeStrategy();
    }
}
