// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/beethovenx/IBeethovenxChef.sol";
import "../../interfaces/beethovenx/IBeetRewarder.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";

import "../Common/StratFeeManager.sol";
import "../../utils/GasFeeThrottler.sol";

contract StrategyBeethovenxDualRewardsMultiRouter is StratFeeManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public output = address(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e);
    address public native = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public spookyRouter = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address public input;
    address public secondOutput;
    address[] public lpTokens;

    // Third party contracts
    address public rewarder;
    address public chef;
    uint256 public chefPoolId;
    bytes32 public wantPoolId;
    bytes32 public nativeSwapPoolId;

    // Routes
    address[] public secondOutputToNativeRoute;
    address[] public nativeToInputRoute;

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        bytes32[] memory _balancerPoolIds,
        uint256 _chefPoolId,
        address _chef,
        CommonAddresses memory _commonAddresses,
        address[] memory _secondOutputToNativeRoute,
        address[] memory _nativeToInputRoute
    ) StratFeeManager(_commonAddresses) {
        wantPoolId = _balancerPoolIds[0];
        nativeSwapPoolId = _balancerPoolIds[1];
        chefPoolId = _chefPoolId;
        chef = _chef;
        secondOutput = _secondOutputToNativeRoute[0];
        secondOutputToNativeRoute = _secondOutputToNativeRoute;
        nativeToInputRoute = _nativeToInputRoute;
        input = _nativeToInputRoute[_nativeToInputRoute.length - 1];

        require(
            _secondOutputToNativeRoute[_secondOutputToNativeRoute.length - 1] == native,
            "_secondOutputToNativeRoute[last] != native"
        );
        require(_nativeToInputRoute[0] == native, "_nativeToInputRoute[0] != native");

        (want, ) = IBalancerVault(unirouter).getPool(wantPoolId);
        rewarder = IBeethovenxChef(chef).rewarder(chefPoolId);

        (lpTokens, , ) = IBalancerVault(unirouter).getPoolTokens(wantPoolId);
        swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IBeethovenxChef(chef).deposit(chefPoolId, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IBeethovenxChef(chef).withdrawAndHarvest(chefPoolId, _amount - wantBal, address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = (wantBal * withdrawalFee) / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
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
        IBeethovenxChef(chef).harvest(chefPoolId, address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 secondOutputBal = IERC20(secondOutput).balanceOf(address(this));
        if (outputBal > 0 || secondOutputBal > 0) {
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
        uint256 toNative = IERC20(output).balanceOf(address(this));
        if (toNative > 0) {
            balancerSwap(nativeSwapPoolId, output, native, toNative);
        }

        toNative = IERC20(secondOutput).balanceOf(address(this));
        if (toNative > 0) {
            IUniswapRouterETH(spookyRouter).swapExactTokensForTokens(
                toNative,
                0,
                secondOutputToNativeRoute,
                address(this),
                block.timestamp
            );
        }

        uint256 nativeBal = (IERC20(native).balanceOf(address(this)) * fees.total) / DIVISOR;

        uint256 callFeeAmount = (nativeBal * fees.call) / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = (nativeBal * fees.beefy) / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = (nativeBal * fees.strategist) / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        IUniswapRouterETH(spookyRouter).swapExactTokensForTokens(
            nativeBal,
            0,
            nativeToInputRoute,
            address(this),
            block.timestamp
        );

        uint256 inputBal = IERC20(input).balanceOf(address(this));
        balancerJoin(wantPoolId, input, inputBal);
    }

    function balancerSwap(
        bytes32 _poolId,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(
            _poolId,
            swapKind,
            _tokenIn,
            _tokenOut,
            _amountIn,
            ""
        );
        return IBalancerVault(unirouter).swap(singleSwap, funds, 1, block.timestamp);
    }

    function balancerJoin(
        bytes32 _poolId,
        address _tokenIn,
        uint256 _amountIn
    ) internal {
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length; ) {
            amounts[i] = lpTokens[i] == _tokenIn ? _amountIn : 0;
            unchecked {
                ++i;
            }
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(
            lpTokens,
            amounts,
            userData,
            false
        );
        IBalancerVault(unirouter).joinPool(_poolId, address(this), address(this), request);
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
        (uint256 _amount, ) = IBeethovenxChef(chef).userInfo(chefPoolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        uint256 rewardBal = IBeetRewarder(rewarder).pendingToken(chefPoolId, address(this));
        return rewardBal;
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            uint256[] memory amountOut = IUniswapRouterETH(spookyRouter).getAmountsOut(
                outputBal,
                secondOutputToNativeRoute
            );
            nativeOut = amountOut[amountOut.length - 1];
        }

        return (((nativeOut * fees.total) / DIVISOR) * fees.call) / DIVISOR;
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

        IBeethovenxChef(chef).emergencyWithdraw(chefPoolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IBeethovenxChef(chef).emergencyWithdraw(chefPoolId, address(this));
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
        IERC20(want).safeApprove(chef, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);
        IERC20(secondOutput).safeApprove(spookyRouter, type(uint256).max);
        if (secondOutput != native) {
            IERC20(native).safeApprove(spookyRouter, type(uint256).max);
        }

        IERC20(input).safeApprove(unirouter, 0);
        IERC20(input).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(secondOutput).safeApprove(spookyRouter, 0);
        IERC20(native).safeApprove(spookyRouter, 0);
        IERC20(input).safeApprove(unirouter, 0);
    }

    function nativeSwapPool() external view returns (bytes32) {
        return nativeSwapPoolId;
    }

    function secondOutputToNative() external view returns (address[] memory) {
        return secondOutputToNativeRoute;
    }

    function nativeToInput() external view returns (address[] memory) {
        return nativeToInputRoute;
    }
}
