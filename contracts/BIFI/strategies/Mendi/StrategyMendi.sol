// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IComptroller.sol";
import "../../interfaces/common/IVToken.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyMendi is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public want;
    address public iToken;
    address[] public rewards;

    // Third party contracts
    address public comptroller;
    address[] public markets;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public balanceOfPool;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _market,
        address _reward,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StratFeeManager_init(_commonAddresses);

        iToken = _market;
        markets.push(_market);
        comptroller = IVToken(_market).comptroller();
        want = IVToken(_market).underlying();

        rewards.push(_reward);
        native = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;

        _giveAllowances();
        IComptroller(comptroller).enterMarkets(markets);
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IVToken(iToken).mint(wantBal);
            _updateBalance();
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            uint err = IVToken(iToken).redeemUnderlying(_amount - wantBal);
            require(err == 0, "Error while trying to redeem");
            _updateBalance();
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

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
        _updateBalance();
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
        uint256 beforeBal = balanceOfWant();
        IComptroller(comptroller).claimComp(address(this), markets);
        _swapToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (want == native) nativeBal -= beforeBal;
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient, nativeBal);
            _swapToWant();
            uint256 wantHarvested = balanceOfWant() - beforeBal;
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient, uint256 rewardBal) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 feeBal = rewardBal * fees.total / DIVISOR;

        uint256 callFeeAmount = feeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = feeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = feeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function _swapToNative() internal {
        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            uint256 rewardBal = IERC20(reward).balanceOf(address(this));
            if (rewardBal > 0) IBeefySwapper(unirouter).swap(reward, native, rewardBal);
        }
    }

    function _swapToWant() internal {
        if (want != native) {
            uint256 nativeBal = IERC20(native).balanceOf(address(this));
            IBeefySwapper(unirouter).swap(native, want, nativeBal);
        }
    }

    function _updateBalance() internal {
        balanceOfPool = IVToken(iToken).balanceOfUnderlying(address(this));
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool;
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public returns (uint256) {
        IComptroller(comptroller).claimComp(address(this), markets);
        return IERC20(rewards[0]).balanceOf(address(this));
    }

    // native reward amount for calling harvest
    function callReward() public returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            nativeOut = IBeefySwapper(unirouter).getAmountOut(rewards[0], native, outputBal);
        }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            super.setWithdrawalFee(0);
        } else {
            super.setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        uint err = IVToken(iToken).redeem(IERC20(iToken).balanceOf(address(this)));
        require(err == 0, "Error while trying to redeem");
        _updateBalance();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        uint err = IVToken(iToken).redeem(IERC20(iToken).balanceOf(address(this)));
        require(err == 0, "Error while trying to redeem");
        _updateBalance();

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
        IERC20(want).safeApprove(iToken, type(uint256).max);
        IERC20(native).safeApprove(unirouter, type(uint256).max);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
            IERC20(rewards[i]).safeApprove(unirouter, type(uint256).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(iToken, 0);
        IERC20(native).safeApprove(unirouter, 0);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
    }

    function setReward(address _reward) external onlyOwner {
        require(_reward != want, "reward==want");
        require(_reward != iToken, "reward==iToken");

        rewards.push(_reward);
        IERC20(_reward).safeApprove(unirouter, type(uint256).max);
    }

    function resetRewards() external onlyManager {
        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            IERC20(reward).safeApprove(unirouter, 0);
        }

        delete rewards;
    }

    receive() external payable {
        IWrappedNative(native).deposit{value: msg.value}();
    }
}