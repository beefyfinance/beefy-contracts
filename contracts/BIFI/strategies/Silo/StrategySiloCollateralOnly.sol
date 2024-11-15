// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBeefySwapper} from "../../interfaces/beefy/IBeefySwapper.sol";
import "../Common/StratFeeManagerInitializable.sol";

interface ISilo {
    function deposit(address asset, uint amount, bool collateralOnly) external;
    function withdraw(address asset, uint amount, bool collateralOnly) external;
    function balanceOf(address user) external view returns (uint256);
}

interface ISiloCollateralToken {
    function asset() external view returns (address);
}

interface ISiloLens {
    function balanceOfUnderlying(uint256 _assetTotalDeposits, address _shareToken, address _user) external view returns (uint256);
    function totalDepositsWithInterest(address _silo, address _asset) external view returns (uint256 _totalDeposits);
    function collateralOnlyDeposits(address _silo, address _asset) external view returns (uint256 _totalCollateral);
}

interface ISiloRewards {
    function claimRewardsToSelf(address[] memory assets, uint256 amount) external;
    function REWARD_TOKEN() external view returns (address);
}

contract StrategySiloCollateralOnly is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public want;
    address public silo;
    address public collateralToken;
    address[] public rewardsClaim;
    address[] public rewards;
    ISiloRewards public incentiveController;
    ISiloLens public lens;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    error InvalidReward();
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _collateralToken,
        address _silo,
        address _native,
        address _lens,
        address _incentiveController,
        CommonAddresses calldata _commonAddresses
     ) public initializer  {
        __StratFeeManager_init(_commonAddresses);
        collateralToken = _collateralToken;
        silo = _silo;
        native = _native;
        want = ISiloCollateralToken(collateralToken).asset();
        incentiveController = ISiloRewards(_incentiveController);
        lens = ISiloLens(_lens);

        rewardsClaim.push(collateralToken);
        rewards.push(incentiveController.REWARD_TOKEN());

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 bal = balanceOfWant();

        if (bal > 0) {
            ISilo(silo).deposit(want, bal, true);
            emit Deposit(balanceOf());
        }
    }

    // Withdraws funds and sends them back to the vault
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            uint256 toWithdraw = _amount - wantBal;
            ISilo(silo).withdraw(want, toWithdraw, true);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = _amount * withdrawalFee / WITHDRAWAL_MAX;
            _amount = _amount - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, _amount);

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

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        incentiveController.claimRewardsToSelf(rewardsClaim, type(uint).max);
        _swapRewardsToNative();
        uint256 bal = IERC20(native).balanceOf(address(this));
        if (bal > 0) {
            chargeFees(callFeeRecipient);
            _swapToWant();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapRewardsToNative() internal {
        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            uint bal = IERC20(reward).balanceOf(address(this));
            if (bal > 0 && reward != native) {
                IBeefySwapper(unirouter).swap(reward, native, bal);
            }
        }
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
    function _swapToWant() internal {
        uint256 bal = IERC20(native).balanceOf(address(this));
        if (want != native) {
            IBeefySwapper(unirouter).swap(native, want, bal);
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
        uint256 totalDeposits = lens.collateralOnlyDeposits(silo, want);
        return lens.balanceOfUnderlying(totalDeposits, collateralToken, address(this));
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

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        uint256 amount = balanceOfPool();
        if (amount > 0) {
            ISilo(silo).withdraw(want, amount, true);
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        uint256 amount = balanceOfPool();
        if (amount > 0) {
            ISilo(silo).withdraw(want, amount, true);
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
        IERC20(native).safeApprove(unirouter, type(uint).max);
        IERC20(want).safeApprove(silo, type(uint).max);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
            IERC20(rewards[i]).safeApprove(unirouter, type(uint).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(want).safeApprove(silo, 0);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
    }

    function setReward(address _reward) external onlyManager {
        if (_reward == collateralToken) revert InvalidReward();
        if (!paused() && _reward != native) IERC20(_reward).safeApprove(unirouter, type(uint).max);
        rewards.push(_reward);
    }

    function resetReward() external onlyManager {
        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
        delete rewards;
    }
}