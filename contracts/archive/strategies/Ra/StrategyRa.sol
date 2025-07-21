// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/ISolidlyGauge.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/UniV3Actions.sol";

contract StrategyRa is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public gauge;
    address public solidlyRouter;

    bool public stable;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    
    address[] public rewards;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _gauge,
        CommonAddresses calldata _commonAddresses
    )  public initializer  {
         __StratFeeManager_init(_commonAddresses);
        want = _want;
        gauge = _gauge;

        stable = ISolidlyPair(want).stable();

        output = address(0xAAAE8378809bb8815c08D3C59Eb0c7D1529aD769);
        native = address(0x5300000000000000000000000000000000000004);
        lpToken0 = ISolidlyPair(want).token0();
        lpToken1 = ISolidlyPair(want).token1();
        solidlyRouter = address(0xAAA45c8F5ef92a000a121d102F4e89278a711Faa);
    
        rewards.push(output);
        _giveAllowances();
    }

    function _rewardExists(address _reward) private view returns (bool exists) {
        for (uint i; i < rewards.length;) {
            if (rewards[i] == _reward) {
                exists = true;
            }
            unchecked { ++i; }
        }
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            ISolidlyGauge(gauge).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ISolidlyGauge(gauge).withdraw(_amount - wantBal);
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

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        ISolidlyGauge(gauge).getReward(address(this), rewards);
        swapRewards();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0)  {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        uint256 beefyFeeAmount = nativeBal - callFeeAmount - strategistFeeAmount;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }
    
    function swapRewards() internal {
        uint256 toNative = IERC20(output).balanceOf(address(this));
        if (toNative > 0) IBeefySwapper(unirouter).swap(output, native, toNative);

        for (uint i; i < rewards.length; ++i) {
            if (rewards[i] != native) {
                uint256 bal = IERC20(rewards[i]).balanceOf(address(this));
                if (bal > 0) {
                    IBeefySwapper(unirouter).swap(rewards[i], native, bal);
                }
            }
        }
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        uint256 lp0Amt = nativeBal / 2;
        uint256 lp1Amt = nativeBal - lp0Amt;

        if (stable) {
            uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
            uint256 out0 = lpToken0 != native
                ? IBeefySwapper(unirouter).getAmountOut(native, lpToken0, lp0Amt) * 1e18 / lp0Decimals
                : lp0Amt;
            uint256 out1 = lpToken1 != native 
                ? IBeefySwapper(unirouter).getAmountOut(native, lpToken1, lp1Amt) * 1e18 / lp1Decimals
                : lp1Amt;
            (uint256 amountA, uint256 amountB,) = ISolidlyRouter(solidlyRouter).quoteAddLiquidity(lpToken0, lpToken1, stable, out0, out1);
            amountA = amountA * 1e18 / lp0Decimals;
            amountB = amountB * 1e18 / lp1Decimals;
            uint256 ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = nativeBal * 1e18 / (ratio + 1e18);
            lp1Amt = nativeBal - lp0Amt;
        }

        if (lpToken0 != native) {
            IBeefySwapper(unirouter).swap(native, lpToken0, lp0Amt);
        }

        if (lpToken1 != native) {
            IBeefySwapper(unirouter).swap(native, lpToken1, lp1Amt);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        ISolidlyRouter(solidlyRouter).addLiquidity(lpToken0, lpToken1, stable, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
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
        return ISolidlyGauge(gauge).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return ISolidlyGauge(gauge).earned(output, address(this));
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

    function deleteRewards() external onlyManager {
        delete rewards;
        rewards.push(output);
    }

    function addRewardToken(address _token) external onlyOwner {
        require (!_rewardExists(_token), "Reward Exists");
        require (_token != address(want), "Reward Token");
        require (_token != address(output), "Output");

        IERC20(_token).safeApprove(unirouter, 0);
        IERC20(_token).safeApprove(unirouter, type(uint).max);

        rewards.push(_token);
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

        ISolidlyGauge(gauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ISolidlyGauge(gauge).withdraw(balanceOfPool());
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
        IERC20(want).safeApprove(gauge, type(uint).max);
        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, type(uint).max);
        }

        IERC20(native).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, type(uint).max);

        IERC20(lpToken0).safeApprove(solidlyRouter, 0);
        IERC20(lpToken0).safeApprove(solidlyRouter, type(uint).max);

        IERC20(lpToken1).safeApprove(solidlyRouter, 0);
        IERC20(lpToken1).safeApprove(solidlyRouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(gauge, 0);
         for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }

        IERC20(native).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(solidlyRouter, 0);
        IERC20(lpToken1).safeApprove(solidlyRouter, 0);
    }
}