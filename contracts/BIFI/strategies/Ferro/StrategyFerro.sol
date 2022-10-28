// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMasterChef.sol";
import "../../interfaces/ferro/IFerroSwap.sol";
import "../../interfaces/ferro/IFerroBoost.sol";
import "../../interfaces/ferro/IFerroBar.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/StringUtils.sol";
import "../../utils/GasFeeThrottler.sol";

contract StrategyFerro is StratFeeManager, GasFeeThrottler {
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
    address public ferroBoost;
    address public xFer;
    uint public stakeId;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    string public pendingRewardsFunctionName;
    uint public maxLoop = 5;
    bool public vestingReady;

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
        address _ferroBoost, 
        address _xFer,
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
        ferroBoost = _ferroBoost;
        xFer = _xFer;

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

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IMasterChef(chef).deposit(poolId, 0);
        if (vestingReady) _claimVested();
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

    // claim vested FER from locked xFER contract, 30 days on from lock
    // deposits/harvests/withdrawals all increment stakeId so multiple claims are needed in one harvest
    function _claimVested() internal {
        uint256 _stakeId = stakeId;
        uint256 _maxLoop = maxLoop;

        for (uint i; i < _maxLoop;) {
            try IFerroBoost(ferroBoost).getUserStake(address(this), _stakeId) 
            returns (IFerroBoost.Stake memory stake) {
                if (block.timestamp > stake.unlockTimestamp) {
                    IFerroBoost(ferroBoost).withdraw(_stakeId);
                    _stakeId += 1;
                } else {
                    break;
                }
            } catch {
                break; 
            }
            unchecked { ++i; }
        }

        stakeId = _stakeId;
        uint256 xFerAmount = IERC20(xFer).balanceOf(address(this));
        if (xFerAmount > 0) {
            IFerroBar(xFer).leavePool(xFerAmount);
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
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToDepositRoute, address(this), block.timestamp);

        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));

        uint256[] memory amounts = new uint256[](poolSize);
        amounts[depositIndex] = depositBal;
        IFerroSwap(pool).addLiquidity(amounts, 0, block.timestamp);
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

    // manually claim vested FER and set the latest stakeId
    function claimVested(uint256[] memory _stakeIds, uint256 _newStakeId) external onlyManager {
        IFerroBoost(ferroBoost).batchWithdraw(_stakeIds);
        uint256 xFerAmount = IERC20(xFer).balanceOf(address(this));
        IFerroBar(xFer).leavePool(xFerAmount);

        stakeId = _newStakeId;
    }

    function setStakeId(uint256 _stakeId) external onlyManager {
        stakeId = _stakeId;
    }

    // set max stakeIds to claim in one harvest
    function setMaxLoop(uint256 _maxLoop) external onlyManager {
        maxLoop = _maxLoop;
    }

    function setVestingReady(bool _vestingReady) external onlyManager {
        vestingReady = _vestingReady;
    }
}
