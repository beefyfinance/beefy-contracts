// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/aave/IAaveV3Incentives.sol";
import "../../interfaces/aave/ILendingPool.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyAaveSupplyOnly is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public want;
    address public aToken;
    address[] public rewards;

    // Third party contracts
    address public lendingPool;
    address public incentivesController;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);
    event SetReward(address reward);

    function initialize(
        address _want,
        address _reward,
        address _native,
        address _aToken,
        address _lendingPool,
        address _incentivesController,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StratFeeManager_init(_commonAddresses);

        want = _want;
        rewards.push(_reward);
        native = _native;

        lendingPool = _lendingPool;
        incentivesController = _incentivesController;

        aToken = _aToken;
        
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            ILendingPool(lendingPool).deposit(want, wantBal, address(this), 0);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();
        if (wantBal < _amount) {
            ILendingPool(lendingPool).withdraw(want, _amount - wantBal, address(this));
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

    function beforeDeposit() external override {
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
        address[] memory assets = new address[](1);
        assets[0] = aToken;
        IAaveV3Incentives(incentivesController).claimAllRewards(assets, address(this));
        _swapRewards();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            _swapToWant();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 stratFees = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = stratFees * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = stratFees * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = stratFees * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // swap rewards to native
    function _swapRewards() internal {
        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            if (reward != native) {
                uint256 rewardBal = IERC20(reward).balanceOf(address(this));
                if (rewardBal > 0) {
                    IBeefySwapper(unirouter).swap(reward, native, rewardBal);
                }
            }
        }
    }

    // swap native to {want}
    function _swapToWant() internal {
        if (native != want) {
            uint256 nativeBal = IERC20(native).balanceOf(address(this));
            IBeefySwapper(unirouter).swap(native, want, nativeBal);
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
        return IERC20(aToken).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public pure returns (uint256) {
        return 0;
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    function setReward(address _reward) external onlyManager {
        require(_reward != want, "reward != want");
        require(_reward != aToken, "reward != aToken");
        rewards.push(_reward);
        IERC20(_reward).safeApprove(unirouter, type(uint256).max);
    }

    function resetReward() external onlyManager {
        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
        delete rewards;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ILendingPool(lendingPool).withdraw(want, type(uint).max, address(this));

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        ILendingPool(lendingPool).withdraw(want, type(uint).max, address(this));
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

    function _giveAllowances() internal {
        IERC20(want).safeApprove(lendingPool, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
            IERC20(rewards[i]).safeApprove(unirouter, type(uint).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(lendingPool, 0);
        IERC20(native).safeApprove(unirouter, 0);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
    }
}
