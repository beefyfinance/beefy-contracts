// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IStableRouter.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyHop is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken;

    // Third party contracts
    address public rewardPool;
    address public stableRouter;
    uint8 public depositIndex;
    uint8 public hTokenIndex;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public slippage = 0.99 ether;
    uint256 public overpool = 1.05 ether;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);
    event SetSlippage(uint256 slippage);
    event SetOverpool(uint256 overpool);

    function __StrategyHop_init(
        address _want,
        address _rewardPool,
        address _stableRouter,
        CommonAddresses calldata _commonAddresses
    ) internal onlyInitializing {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        rewardPool = _rewardPool;
        stableRouter = _stableRouter;

        lpToken = IRewardPool(rewardPool).stakingToken();
        depositIndex = IStableRouter(stableRouter).getTokenIndex(want);
        hTokenIndex = depositIndex == 0 ? 1 : 0;
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            uint256[] memory inputs = new uint256[](2);
            inputs[depositIndex] = IERC20(want).balanceOf(address(this));

            // check that the pool is balanced in our favor
            uint256 wantTokenBal = IStableRouter(stableRouter).getTokenBalances(depositIndex);
            uint256 hTokenBal = IStableRouter(stableRouter).getTokenBalances(hTokenIndex);
            require(wantTokenBal < hTokenBal * overpool / 1 ether, "want overpooled in LP");

            IStableRouter(stableRouter).addLiquidity(inputs, 1, block.timestamp);
            IRewardPool(rewardPool).stake(IERC20(lpToken).balanceOf(address(this)));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            uint256 amountToWithdraw = _amount - wantBal;
            uint256 lpBal = IERC20(lpToken).balanceOf(address(this));
            uint256 stakedLpBal = IRewardPool(rewardPool).balanceOf(address(this));

            uint256 lpBalToWithdraw = (lpBal + stakedLpBal) * amountToWithdraw / balanceOfPool();
            if (lpBalToWithdraw > lpBal) {
                IRewardPool(rewardPool).withdraw(lpBalToWithdraw - lpBal);
            }

            // remove liquidity to 'want' with slippage protection
            IStableRouter(stableRouter).removeLiquidityOneToken(
                lpBalToWithdraw,
                depositIndex,
                amountToWithdraw * slippage / 1 ether,
                block.timestamp
            );

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

    function beforeDeposit() external virtual override {
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

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal {
        IRewardPool(rewardPool).getReward();
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 before = IERC20(native).balanceOf(address(this));
        _swapToNative(fees.total);
        uint256 nativeFeeBal = IERC20(native).balanceOf(address(this)) - before;

        uint256 callFeeAmount = nativeFeeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeFeeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeFeeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
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
        uint256 lpBal = IERC20(lpToken).balanceOf(address(this)) 
            + IRewardPool(rewardPool).balanceOf(address(this));
        uint256 lpPrice = IStableRouter(stableRouter).getVirtualPrice();

        return lpBal * lpPrice / 1 ether;
    }

    function rewardsAvailable() public view returns (uint256) {
        return IRewardPool(rewardPool).earned(address(this));
    }

    function callReward() public view returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;

        nativeOut = _getAmountOut(outputBal);

        IFeeConfig.FeeCategory memory fees = getFees();
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

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        
        uint256 stakedLpBal = IRewardPool(rewardPool).balanceOf(address(this));
        if (stakedLpBal > 0) {
            IRewardPool(rewardPool).withdraw(stakedLpBal);
        }

        uint256 lpBal = IERC20(lpToken).balanceOf(address(this));
        IERC20(lpToken).safeApprove(stableRouter, 0);
        IERC20(lpToken).safeApprove(stableRouter, type(uint).max);
        if (lpBal > 0) {
            IStableRouter(stableRouter).removeLiquidityOneToken(
                lpBal,
                depositIndex,
                balanceOfPool() * slippage / 1 ether,
                block.timestamp
            );
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        IRewardPool(rewardPool).withdraw(IRewardPool(rewardPool).balanceOf(address(this)));
        try IStableRouter(stableRouter).removeLiquidityOneToken(
            IERC20(lpToken).balanceOf(address(this)),
            depositIndex,
            balanceOfPool() * slippage / 1 ether,
            block.timestamp
        ) {} catch {}
        pause();
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

    function _giveAllowances() internal virtual {
        IERC20(want).safeApprove(stableRouter, type(uint).max);
        IERC20(lpToken).safeApprove(stableRouter, type(uint).max);
        IERC20(lpToken).safeApprove(rewardPool, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal virtual {
        IERC20(want).safeApprove(stableRouter, 0);
        IERC20(lpToken).safeApprove(stableRouter, 0);
        IERC20(lpToken).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function setSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage < 1 ether, ">slippageMax");
        slippage = _slippage;
        emit SetSlippage(_slippage);
    }

    function setOverpool(uint256 _overpool) external onlyOwner {
        require(_overpool > 1 ether, "<overpoolMin");
        overpool = _overpool;
        emit SetOverpool(_overpool);
    }

    function _swapToNative(uint256 totalFee) internal virtual {}

    function _swapToWant() internal virtual {}

    function _getAmountOut(uint256 inputAmount) internal view virtual returns (uint256) {}

    function outputToNative() external view virtual returns (address[] memory) {}

    function outputToWant() external view virtual returns (address[] memory) {}
}
