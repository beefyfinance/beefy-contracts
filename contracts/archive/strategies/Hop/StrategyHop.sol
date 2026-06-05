// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyHop is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public native;
    address public reward;
    address public depositToken;

    // Third party contracts
    address public rewardPool;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _depositToken,
        address _rewardPool,
        address _native,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StratFeeManager_init(_commonAddresses);
        want = IRewardPool(_rewardPool).stakingToken();
        native = _native;
        rewardPool = _rewardPool;
        reward = IRewardPool(_rewardPool).rewardsToken();
        depositToken = _depositToken;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardPool(rewardPool).stake(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
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
    function _harvest(address callFeeRecipient) internal {
        IRewardPool(rewardPool).getReward();
        _swapToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            _addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapToNative() internal {
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));
        if (rewardBal > 0) IBeefySwapper(unirouter).swap(reward, native, rewardBal);
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeFeeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeFeeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeFeeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeFeeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function _addLiquidity() internal {
        if (depositToken != native) {
            uint256 nativeBal = IERC20(native).balanceOf(address(this));
            IBeefySwapper(unirouter).swap(native, depositToken, nativeBal);
        }
        uint256 depositTokenBal = IERC20(depositToken).balanceOf(address(this));
        IBeefySwapper(unirouter).swap(depositToken, want, depositTokenBal);
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
        return IRewardPool(rewardPool).balanceOf(address(this));
    }

    function rewardsAvailable() public view returns (uint256) {
        return IRewardPool(rewardPool).earned(address(this));
    }

    function callReward() public view returns (uint256) {
        uint256 rewardBal = rewardsAvailable();
        uint256 nativeOut = IBeefySwapper(unirouter).getAmountOut(reward, native, rewardBal);

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

    function _giveAllowances() internal virtual {
        IERC20(want).safeApprove(rewardPool, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        IERC20(reward).safeApprove(unirouter, type(uint).max);
        if (depositToken != native) IERC20(depositToken).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal virtual {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(reward).safeApprove(unirouter, 0);
        if (depositToken != native) IERC20(depositToken).safeApprove(unirouter, 0);
    }

    function setRewardPool(address _rewardPool) external onlyOwner {
        require(want == IRewardPool(_rewardPool).stakingToken(), "!want");
        address _reward = IRewardPool(_rewardPool).rewardsToken();
        require(_reward != want, "want=reward");
        require(_reward != native, "native=reward");
        require(_reward != depositToken, "native=deposit");

        if (balanceOfPool() > 0) IRewardPool(rewardPool).withdraw(balanceOfPool());
        IERC20(reward).safeApprove(unirouter, 0);

        rewardPool = _rewardPool;
        reward = _reward;
        
        if (!paused()) {
            IERC20(_reward).safeApprove(unirouter, type(uint).max);
            deposit();
        }
    }
}
