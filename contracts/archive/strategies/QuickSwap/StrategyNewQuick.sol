// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../utils/AlgebraUtils.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyNewQuick is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;

    // Third party contracts
    address public rewardPool;

    // Routes
    bytes public outputToNativePath;
    bytes public outputToWantPath;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _rewardPool,
        address[] calldata _outputToNativeRoute,
        address[] calldata _outputToWantRoute,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        rewardPool = _rewardPool;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        want = _outputToWantRoute[_outputToWantRoute.length - 1];

        outputToNativePath = AlgebraUtils.routeToPath(_outputToNativeRoute);

        require(_outputToWantRoute[0] == output, "toWant[0] != output");
        outputToWantPath = AlgebraUtils.routeToPath(_outputToWantRoute);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IRewardPool(rewardPool).stake(wantBal);
            emit Deposit(wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IRewardPool(rewardPool).withdraw(_amount - wantBal);
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
        IRewardPool(rewardPool).getReward();

        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            swapRewards();
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

        AlgebraUtils.swap(unirouter, outputToNativePath, toNative);
        uint256 feeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = feeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = feeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = feeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // swap rewards to want
    function swapRewards() internal {
        if (want != output) {
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            AlgebraUtils.swap(unirouter, outputToWantPath, outputBal);
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
        return IRewardPool(rewardPool).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IRewardPool(rewardPool).earned(address(this));
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardPool(rewardPool).withdraw(balanceOfPool());

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit == true) {
            super.setWithdrawalFee(0);
        } else {
            super.setWithdrawalFee(10);
        }
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

    function outputToNative() public view returns (address[] memory) {
        return AlgebraUtils.pathToRoute(outputToNativePath);
    }

    function outputToWant() public view returns (address[] memory) {
        return AlgebraUtils.pathToRoute(outputToWantPath);
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(rewardPool, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function swapRewardPool(
        address _rewardPool,
        address[] calldata _outputToNativeRoute,
        address[] calldata _outputToWantRoute
    ) external onlyOwner {
        require(want == IRewardPool(_rewardPool).stakingToken(), "Proposal not valid for this Vault");
        require((_outputToNativeRoute[0] == IRewardPool(_rewardPool).rewardsToken())
            && (want != IRewardPool(_rewardPool).rewardsToken()),
            "Proposed output in route is not valid"
        );
        require(want == _outputToWantRoute[_outputToWantRoute.length - 1], 
            "Proposed want in route not valid"
        );

        IRewardPool(rewardPool).withdraw(balanceOfPool());
        _removeAllowances();

        rewardPool = _rewardPool;
        output = _outputToNativeRoute[0];
        outputToNativePath = AlgebraUtils.routeToPath(_outputToNativeRoute);
        outputToWantPath = AlgebraUtils.routeToPath(_outputToWantRoute);

        _giveAllowances();
        IRewardPool(rewardPool).stake(balanceOfWant());
    }
}