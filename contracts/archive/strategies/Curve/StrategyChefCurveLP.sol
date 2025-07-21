// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMasterChef.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/StringUtils.sol";
import "../../utils/GasFeeThrottler.sol";

contract StrategyChefCurveLP is StratFeeManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public depositToken;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public pool;
    uint public poolSize;
    uint public depositIndex;
    bool public useMetapool;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    string public pendingRewardsFunctionName;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToDepositRoute;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _pool,
        uint _poolSize,
        uint _depositIndex,
        bool _useMetapool,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToDepositRoute,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        want = _want;
        poolId = _poolId;
        chef = _chef;
        pool = _pool;
        poolSize = _poolSize;
        depositIndex = _depositIndex;
        useMetapool = _useMetapool;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        require(_outputToDepositRoute[0] == output, '_outputToDepositRoute[0] != output');
        depositToken = _outputToDepositRoute[_outputToDepositRoute.length - 1];
        outputToDepositRoute = _outputToDepositRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(chef).deposit(poolId, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(chef).withdraw(poolId, _amount - wantBal);
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

    function harvest() external virtual gasThrottle {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual gasThrottle {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IMasterChef(chef).deposit(poolId, 0);
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
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 toNative = IERC20(output).balanceOf(address(this)) * fees.total / DIVISOR;
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

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
        if (depositToken != output) {
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToDepositRoute, address(this), block.timestamp);
        }

        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useMetapool) ICurveSwap(pool).add_liquidity(want, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 4) {
            uint256[4] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useMetapool) ICurveSwap(pool).add_liquidity(want, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 5) {
            uint256[5] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap(pool).add_liquidity(amounts, 0);
        }
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
        (uint256 _amount,) = IMasterChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function setPendingRewardsFunctionName(string calldata _pendingRewardsFunctionName) external onlyManager {
        pendingRewardsFunctionName = _pendingRewardsFunctionName;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
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

        IFeeConfig.FeeCategory memory fees = getFees();
        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
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

        IMasterChef(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMasterChef(chef).emergencyWithdraw(poolId);
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
        IERC20(depositToken).safeApprove(pool, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(depositToken).safeApprove(pool, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToDeposit() external view returns (address[] memory) {
        return outputToDepositRoute;
    }
}
