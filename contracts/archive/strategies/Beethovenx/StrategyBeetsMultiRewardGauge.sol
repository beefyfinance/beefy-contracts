// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/beethovenx/IBalancerVault.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../../interfaces/curve/IHelper.sol";
import "../Common/StratFeeManager.sol";

contract StrategyBeetsMultiRewardGauge is StratFeeManager {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public output = address(0x97513e975a7fA9072c72C92d8000B0dB90b163c5);
    address public helper = address(0x299dcDF14350999496204c141A0c20A29d71AF3E);
    address public native = address(0x4200000000000000000000000000000000000006);
    address public op = address(0x4200000000000000000000000000000000000042);
    address public input;
    address[] public lpTokens;

    struct Reward {
        address token;
        bytes32 rewardSwapPoolId;
        uint minAmount; // minimum amount to be swapped to native
    }

    Reward[] public rewards;

    // Third party contracts
    address public rewardsGauge;
    bytes32 public wantPoolId;
    bytes32 public nativeSwapPoolId;
    bytes32 public inputSwapPoolId;
    bytes32 public opSwapPoolId;

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        bytes32[] memory _balancerPoolIds,
        address _rewardsGauge,
        address _input,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        wantPoolId = _balancerPoolIds[0];
        nativeSwapPoolId = _balancerPoolIds[1];
        inputSwapPoolId = _balancerPoolIds[2];
        opSwapPoolId = _balancerPoolIds[3];
        rewardsGauge = _rewardsGauge;

        (want,) = IBalancerVault(unirouter).getPool(wantPoolId);
        input = _input;

        (lpTokens,,) = IBalancerVault(unirouter).getPoolTokens(wantPoolId);
        swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardsGauge(rewardsGauge).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IRewardsGauge(rewardsGauge).withdraw(_amount - wantBal);
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
        IHelper(helper).claimRewards(rewardsGauge, address(this));
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }
    function swapRewardsToNative() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            balancerSwap(opSwapPoolId, output, op, outputBal);
            uint256 opBal = IERC20(op).balanceOf(address(this));
            balancerSwap(nativeSwapPoolId, op, native, opBal);
        }
        // extras
        for (uint i; i < rewards.length;) {
            uint bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount && rewards[i].token != op) {
                balancerSwap(rewards[i].rewardSwapPoolId, rewards[i].token, op, bal);
            }
            uint256 opBal = IERC20(op).balanceOf(address(this));
            balancerSwap(nativeSwapPoolId, op, native, opBal);
            unchecked { ++i; }
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
    function addLiquidity() internal {
        if (input != native) {
            uint256 nativeBal = IERC20(native).balanceOf(address(this));
            balancerSwap(inputSwapPoolId, native, input, nativeBal);
        }

        uint256 inputBal = IERC20(input).balanceOf(address(this));
        balancerJoin(wantPoolId, input, inputBal);
    }

    function balancerSwap(bytes32 _poolId, address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(_poolId, swapKind, _tokenIn, _tokenOut, _amountIn, "");
        return IBalancerVault(unirouter).swap(singleSwap, funds, 1, block.timestamp);
    }

    function balancerJoin(bytes32 _poolId, address _tokenIn, uint256 _amountIn) internal {
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length;) {
            amounts[i] = lpTokens[i] == _tokenIn ? _amountIn : 0;
            unchecked { ++i; }
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(lpTokens, amounts, userData, false);
        IBalancerVault(unirouter).joinPool(_poolId, address(this), address(this), request);
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
        return IRewardsGauge(rewardsGauge).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IRewardsGauge(rewardsGauge).claimable_reward(address(this), output);
    }

    // native reward amount for calling harvest
    function callReward() public returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            nativeOut = balancerSwap(nativeSwapPoolId, output, native, outputBal);
        }

        if (rewards.length != 0) {
            for (uint i; i < rewards.length; ++i) {
                uint256 rewardBal = IERC20(rewards[i].token).balanceOf(address(this));
                if (rewardBal > 0) {
                    nativeOut += balancerSwap(rewards[i].rewardSwapPoolId, rewards[i].token, native, rewardBal);
                }
            }
        }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

     function addRewardToken(address _token, bytes32 _rewardSwapPoolId, uint _minAmount) external onlyOwner {
        require(_token != want, "!want");
        require(_token != native, "!native");

        rewards.push(Reward(_token, _rewardSwapPoolId, _minAmount));
        IERC20(_token).safeApprove(unirouter, 0);
        IERC20(_token).safeApprove(unirouter, type(uint).max);
    }

     function resetRewardTokens() external onlyManager {
        delete rewards;
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

        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IRewardsGauge(rewardsGauge).withdraw(balanceOfPool());
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
        IERC20(want).safeApprove(rewardsGauge, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);
        IERC20(op).safeApprove(unirouter, type(uint).max);
        if (rewards.length != 0) {
            for (uint i; i < rewards.length;) {
                IERC20(rewards[i].token).safeApprove(unirouter, type(uint).max);
                unchecked { ++i; }
            }
        }

        IERC20(input).safeApprove(unirouter, 0);
        IERC20(input).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(rewardsGauge, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(op).safeApprove(unirouter, 0);
        if (rewards.length != 0) { 
            for (uint i; i < rewards.length;) {
                IERC20(rewards[i].token).safeApprove(unirouter, 0);
                unchecked { ++i; }
            }
        }

        IERC20(input).safeApprove(unirouter, 0);
    }
}
