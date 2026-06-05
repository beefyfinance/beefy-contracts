// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/gmx/IGMXRouter.sol";
import "../../interfaces/gmx/IGMXTracker.sol";
import "../../interfaces/gmx/IGLPManager.sol";
import "../../interfaces/gmx/IBeefyVault.sol";
import "../../interfaces/gmx/IGMXStrategy.sol";
import "../../interfaces/gmx/IFeeStakedOLP.sol";
import "../../utils/UniswapV3Utils.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyOLP is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public native;
    address public output;

    // Third party contracts
    address public chef;
    address public glpManager;
    address public fOLP;
    address public fsOLP;

    // Route
    bytes public outputToNativePath;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    bool public cooldown;
    uint256 public extraCooldownDuration = 900;
    bool public extraReward;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _chef,
        address _fsOLP,
        address[] memory _outputToNativeRoute,
        uint24[] memory _outputToNativeFees,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        chef = _chef;
        fsOLP = _fsOLP;
        extraReward = true;

        fOLP = IGMXRouter(chef).feeGlpTracker();
        glpManager = IGMXRouter(chef).glpManager();
        
        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length -1];

        outputToNativePath = UniswapV3Utils.routeToPath(_outputToNativeRoute, _outputToNativeFees);

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
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0 && extraReward) {
            IFeeStakedOLP(fsOLP).stake(fOLP, wantBal);
        }
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IFeeStakedOLP(fsOLP).unstake(fOLP, _amount - wantBal);
            wantBal = balanceOfWant();
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
        if (extraReward) {
            IFeeStakedOLP(fsOLP).claim(address(this));
        }
        IFeeStakedOLP(fOLP).claim(address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (outputBal > 0 || nativeBal > 0) {
            chargeFees(callFeeRecipient);
            mintOlp();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0 && output != native) {
            UniswapV3Utils.swap(unirouter, outputToNativePath, outputBal);
        }

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

    // mint more GLP with the ETH earned as fees
    function mintOlp() internal whenNotCooling {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        IGMXRouter(chef).mintAndStakeGlp(native, nativeBal, 0, 0);
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
        return IERC20(fsOLP).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        uint256 rewardGLP = IGMXTracker(fOLP).claimable(address(this));
        return rewardGLP;
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = rewardsAvailable();

        return nativeBal * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    // called as part of strat migration. Transfers all want, GLP, esGMX and MP to new strat.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        uint256 fsOLPBal = balanceOfPool();
        if (fsOLPBal > 0) {
            IFeeStakedOLP(fsOLP).unstake(fOLP, fsOLPBal);
        }

        IBeefyVault.StratCandidate memory candidate = IBeefyVault(vault).stratCandidate();
        address stratAddress = candidate.implementation;

        IGMXRouter(chef).signalTransfer(stratAddress);
        IGMXStrategy(stratAddress).acceptTransfer();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        uint256 fsOLPBal = balanceOfPool();
        if (fsOLPBal > 0) {
            IFeeStakedOLP(fsOLP).unstake(fOLP, fsOLPBal);
        }
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
        IERC20(native).safeApprove(glpManager, type(uint).max);
        
        if (extraReward) {
            IERC20(output).safeApprove(unirouter, type(uint).max);
            IERC20(fOLP).safeApprove(fsOLP, type(uint).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(glpManager, 0);
        IERC20(fOLP).safeApprove(fsOLP, 0);
    }

    // timestamp at which withdrawals open again
    function withdrawOpen() public view returns (uint256) {
        return IGLPManager(glpManager).lastAddedAt(address(this)) 
            + IGLPManager(glpManager).cooldownDuration();
    }

    // turn on extra cooldown time to allow users to withdraw
    function setCooldown(bool _cooldown) external onlyManager {
        cooldown = _cooldown;
    }

    // set the length of cooldown time for withdrawals
    function setExtraCooldownDuration(uint256 _extraCooldownDuration) external onlyManager {
        extraCooldownDuration = _extraCooldownDuration;
    }

    function removeExtraReward() external onlyManager {
        extraReward = false;

        IERC20(output).safeApprove(unirouter, 0);
        IERC20(fOLP).safeApprove(fsOLP, 0);
        uint256 fsOLPBal = balanceOfPool();
        if (fsOLPBal > 0) {
            IFeeStakedOLP(fsOLP).unstake(fOLP, fsOLPBal);
        }
    }

    function setExtraReward(
        address _fsOLP,
        address[] memory _outputToNativeRoute,
        uint24[] memory _outputToNativeFees
    ) external onlyOwner {
        require(!extraReward, "already has reward");
        extraReward = true;

        fsOLP = _fsOLP;
        output = _outputToNativeRoute[0];
        outputToNativePath = UniswapV3Utils.routeToPath(_outputToNativeRoute, _outputToNativeFees);

        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(fOLP).safeApprove(fsOLP, type(uint).max);
        deposit();
    }

    // accept transfer of migrating fOLP into this strat
    function acceptTransfer() external {
        address prevStrat = IBeefyVault(vault).strategy();
        require(msg.sender == prevStrat, "!prevStrat");
        IGMXRouter(chef).acceptTransfer(prevStrat);
    }

    function outputToNative() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToNativePath);
    }
}