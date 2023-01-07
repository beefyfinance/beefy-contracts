// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/mvx/IMVXRouter.sol";
import "../../interfaces/gmx/IGMXTracker.sol";
import "../../interfaces/gmx/IGLPManager.sol";
import "../../interfaces/gmx/IBeefyVault.sol";
import "../../interfaces/gmx/IGMXStrategy.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyMVLP is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public native;

    // Third party contracts
    address public minter;
    address public chef;
    address public mvlpRewardStorage;
    address public mvxRewardStorage;
    address public mvlpManager;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    bool public cooldown;
    uint256 public extraCooldownDuration = 900;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _native,
        address _minter,
        address _chef,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        native = _native;
        minter = _minter;
        chef = _chef;

        mvlpRewardStorage = IMVXRouter(chef).feeMvlpTracker();
        mvxRewardStorage = IMVXRouter(chef).feeMvxTracker();
        mvlpManager = IMVXRouter(minter).mvlpManager();

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
        IMVXRouter(chef).compound();   // Claim and restake esMVX and multiplier points
        IMVXRouter(chef).claimFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            uint256 before = balanceOfWant();
            mintMvlp();
            uint256 wantHarvested = balanceOfWant() - before;

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
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

    // mint more MVLP with the MATIC earned as fees
    function mintMvlp() internal whenNotCooling {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        IMVXRouter(minter).mintAndStakeMvlp(native, nativeBal, 0, 0);
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
        uint256 rewardMVLP = IGMXTracker(mvlpRewardStorage).claimable(address(this));
        uint256 rewardMVX = IGMXTracker(mvxRewardStorage).claimable(address(this));
        return rewardMVLP + rewardMVX;
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

    // called as part of strat migration. Transfers all want, MVLP, esMVX and MP to new strat.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IBeefyVault.StratCandidate memory candidate = IBeefyVault(vault).stratCandidate();
        address stratAddress = candidate.implementation;

        IMVXRouter(chef).signalTransfer(stratAddress);
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
        IERC20(native).safeApprove(mvlpManager, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(native).safeApprove(mvlpManager, 0);
    }

    // timestamp at which withdrawals open again
    function withdrawOpen() public view returns (uint256) {
        return IGLPManager(mvlpManager).lastAddedAt(address(this)) 
            + IGLPManager(mvlpManager).cooldownDuration();
    }

    // turn on extra cooldown time to allow users to withdraw
    function setCooldown(bool _cooldown) external onlyManager {
        cooldown = _cooldown;
    }

    // set the length of cooldown time for withdrawals
    function setExtraCooldownDuration(uint256 _extraCooldownDuration) external onlyManager {
        extraCooldownDuration = _extraCooldownDuration;
    }

    function acceptTransfer() external {
        address prevStrat = IBeefyVault(vault).strategy();
        require(msg.sender == prevStrat, "!prevStrat");
        IMVXRouter(chef).acceptTransfer(prevStrat);

        // send back 1 wei to complete upgrade
        IERC20(want).safeTransfer(prevStrat, 1);
    }
}
