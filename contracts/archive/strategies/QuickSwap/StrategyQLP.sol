// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/utils/math/Math.sol";

import "../../interfaces/quick/IQlpRouter.sol";
import "../../interfaces/quick/IQlpTracker.sol";
import "../../interfaces/quick/IQlpManager.sol";
import "../../interfaces/gmx/IBeefyVault.sol";
import "../../interfaces/gmx/IGMXStrategy.sol";
import "../../utils/AlgebraUtils.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyQLP is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    struct Reward {
        address token;
        bytes path;
        uint256 minSwap;
    }

    // Tokens used
    address public want;
    address public native;
    Reward[] public rewards;

    // Third party contracts
    address public rewardRouter;
    address public rewardTracker;
    address public qlpManager;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    bool public cooldown;
    uint256 public extraCooldownDuration = 900;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);
    event ClaimReward(address reward, uint256 amount);
    event UpdateReward(address reward, uint256 amount, uint256 rate);

    function initialize(
        address _want,
        address _native,
        address _rewardRouter,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        native = _native;
        rewardRouter = _rewardRouter;

        rewardTracker = IQlpRouter(rewardRouter).feeQlpTracker();
        qlpManager = IQlpRouter(rewardRouter).qlpManager();

        _giveAllowances();
    }

    // prevent griefing by preventing deposits for longer than the cooldown period
    modifier whenNotCooling {
        if (cooldown) {
            require(block.timestamp >= withdrawOpen() + extraCooldownDuration, "cooldown");
        }
        _;
    }

    // puts the funds to work
    function deposit() public whenNotPaused whenNotCooling {
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

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
        IQlpRouter(rewardRouter).handleRewards(false, false);
        swapRewards();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            uint256 before = balanceOfWant();
            mintQlp();
            uint256 wantHarvested = balanceOfWant() - before;

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // swap to native
    function swapRewards() internal {
        for (uint i; i < rewards.length;) {
            Reward memory reward = rewards[i];
            uint256 amount = IERC20(reward.token).balanceOf(address(this));
            if (amount > reward.minSwap) AlgebraUtils.swap(unirouter, reward.path, amount);
            unchecked { ++i; }
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 feeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = feeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = feeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = feeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // mint more QLP with the ETH earned as fees
    function mintQlp() internal whenNotCooling {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        IQlpRouter(rewardRouter).mintAndStakeQlp(native, nativeBal, 0, 0);
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
    function balanceOfPool() public pure returns (uint256) {
        return 0;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IQlpTracker(rewardTracker).claimable(address(this), native);
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = rewardsAvailable();

        return nativeBal * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Transfers all want to vault
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IBeefyVault.StratCandidate memory candidate = IBeefyVault(vault).stratCandidate();
        address stratAddress = candidate.implementation;

        IQlpRouter(rewardRouter).signalTransfer(stratAddress);
        IGMXStrategy(stratAddress).acceptTransfer();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();
    }

    function _giveAllowances() internal {
        IERC20(native).safeApprove(qlpManager, type(uint).max);

        for (uint i; i < rewards.length;) {
            IERC20(rewards[i].token).safeApprove(unirouter, type(uint).max);
            unchecked { ++i; }
        }
    }

    function _removeAllowances() internal {
        IERC20(native).safeApprove(qlpManager, 0);

        for (uint i; i < rewards.length;) {
            IERC20(rewards[i].token).safeApprove(unirouter, 0);
            unchecked { ++i; }
        }
    }

    // timestamp at which withdrawals open again
    function withdrawOpen() public view returns (uint256) {
        return IQlpManager(qlpManager).lastAddedAt(address(this)) 
            + IQlpManager(qlpManager).cooldownDuration();
    }

    // turn on extra cooldown time to allow users to withdraw
    function setCooldown(bool _cooldown) external onlyManager {
        cooldown = _cooldown;
    }

    // set the length of cooldown time for withdrawals
    function setExtraCooldownDuration(uint256 _extraCooldownDuration) external onlyManager {
        extraCooldownDuration = _extraCooldownDuration;
    }

    // called as part of migration from previous strategy
    function acceptTransfer() external {
        address prevStrat = IBeefyVault(vault).strategy();
        require(msg.sender == prevStrat, "!prevStrat");
        IQlpRouter(rewardRouter).acceptTransfer(prevStrat);

        // send back 1 wei to complete upgrade
        IERC20(want).safeTransfer(prevStrat, 1);
    }

    // add reward to vest over a period
    function addReward(
        address _token,
        bytes calldata _path,
        uint256 _minSwap
    ) external onlyOwner {
        require(_token != want, "!want");
        require(_token != native, "!native");
        IERC20(_token).safeApprove(unirouter, type(uint).max);

        Reward memory reward = Reward(_token, _path, _minSwap);
        rewards.push(reward);
    }

    // remove all extra rewards
    function resetReward() external onlyManager {
        for (uint i; i < rewards.length;) {
            IERC20(rewards[i].token).safeApprove(unirouter, 0);
            unchecked { ++i; }
        }
        delete rewards;
    }
}
