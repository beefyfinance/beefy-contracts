// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";
import "../../interfaces/swapbased/ISwapBasedOption.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategySwapBased is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;
    address public option;
    address[] public rewards;

    // Third party contracts
    address public rewardPool;
    address public constant balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public swapBasedRouter;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public duration;
    
    uint256 private lock;
    bool private flash;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    modifier whenUnlocked() {
        require(lock != 1, "locked");
        _;
    }

    function initialize(
        address _want,
        address _rewardPool,
        address _native,
        address _output,
        address _option,
        address _swapBasedRouter,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        rewardPool = _rewardPool;
        native = _native;
        output = _output;
        option = _option;
        swapBasedRouter = _swapBasedRouter;

        // setup lp routing
        lpToken0 = IUniswapV2Pair(want).token0();
        lpToken1 = IUniswapV2Pair(want).token1();

        duration = 1 hours;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused whenUnlocked {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardPool(rewardPool).stake(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external whenUnlocked {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IRewardPool(rewardPool).withdraw(_amount - wantBal);
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
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IRewardPool(rewardPool).getReward();
        _convertRewards();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            totalLocked = wantHarvested + lockedProfit();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _convertRewards() internal {
        // unwrap any native
        uint256 nativeBal = address(this).balance;
        if (nativeBal > 0) IWrappedNative(native).deposit{value: nativeBal}();

        // convert additional rewards
        if (rewards.length != 0) {
            for (uint i; i < rewards.length; i++) {
                address reward = rewards[i];
                uint256 toNative = IERC20(reward).balanceOf(address(this));
                if (toNative > 0) IBeefySwapper(unirouter).swap(reward, native, toNative);
            }
        }

        uint256 optionBal = IERC20(option).balanceOf(address(this));
        if (optionBal > 0) {
            uint256 exchangeRate = ISwapBasedOption(option).quotePrice(optionBal);
            uint256 twapRate = IBeefySwapper(unirouter).getAmountOut(output, native, optionBal);
            require(exchangeRate > (twapRate * 95 / 100), "volatile");
            uint256 nativeRequired = ISwapBasedOption(option).quotePayment(optionBal) * 11 / 10;

            address[] memory tokens = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            tokens[0] = native;
            amounts[0] = nativeRequired;

            flash = true;
            IBalancerVault(balancerVault).flashLoan(address(this), tokens, amounts, '');
        }
    }

    function receiveFlashLoan(
        address[] memory /*tokens*/,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory /*userData*/
    ) external {
        require(flash == true, "!initiated");
        flash = false;

        ISwapBasedOption(option).instantExit(IERC20(option).balanceOf(address(this)), amounts[0]);
        IBeefySwapper(unirouter).swap(output, native, IERC20(output).balanceOf(address(this)));
        IERC20(native).safeTransfer(balancerVault, amounts[0] + feeAmounts[0]);
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
        if (lpToken0 != native) IBeefySwapper(unirouter).swap(native, lpToken0, nativeHalf);
        if (lpToken1 != native) IBeefySwapper(unirouter).swap(native, lpToken1, nativeHalf);

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IUniswapRouterETH(swapBasedRouter).addLiquidity(
            lpToken0, lpToken1, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp
        );
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return IRewardPool(rewardPool).balanceOf(address(this));
    }

    function lockedProfit() public view returns (uint256) {
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < duration ? duration - elapsed : 0;
        return totalLocked * remaining / duration;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IRewardPool(rewardPool).earned(address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            nativeOut = IBeefySwapper(unirouter).getAmountOut(output, native, outputBal);
        }

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

    function setOption(address _option) external onlyOwner {
        IERC20(native).safeApprove(option, 0);
        option = _option;
        if (!paused()) IERC20(native).safeApprove(_option, type(uint).max);
    }

    // locks deposits and withdrawals until lock is called again, single use
    function setLock() external onlyManager {
        if (lock < 2) lock++;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardPool(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IRewardPool(rewardPool).withdraw(balanceOfPool());
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
        IERC20(want).safeApprove(rewardPool, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(option, type(uint).max);
        IERC20(lpToken0).safeApprove(swapBasedRouter, type(uint).max);
        IERC20(lpToken1).safeApprove(swapBasedRouter, type(uint).max);

        for (uint i; i < rewards.length; i++) {
            IERC20(rewards[i]).safeApprove(unirouter, type(uint).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(option, 0);
        IERC20(lpToken0).safeApprove(swapBasedRouter, 0);
        IERC20(lpToken1).safeApprove(swapBasedRouter, 0);

        for (uint i; i < rewards.length; i++) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
    }

    function addReward(address _reward) external onlyOwner {
        IERC20(_reward).safeApprove(unirouter, type(uint).max);
        rewards.push(_reward);
    }

    function removeLastReward() external onlyManager {
        address reward = rewards[rewards.length - 1];
        IERC20(reward).safeApprove(unirouter, 0);
        rewards.pop();
    }

    function depositFee() public override pure returns (uint256) {
        return 100;
    }

    receive () external payable {}
}
