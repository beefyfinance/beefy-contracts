// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/aura/IAuraBooster.sol";
import "../../interfaces/aura/IAuraRewardPool.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "./BalancerActionsLib.sol";
import "./BeefyBalancerStructs.sol";
import "../../utils/UniV3Actions.sol";

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
    function getTokenRates() external view returns (uint256, uint256);
}

contract StrategyAuraGyroMainnet is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    uint256 public constant DURATION = 1 days;

    // Tokens used
    address public want;
    address public output;
    address public native;
    address public lp0;
    address public lp1;

    BeefyBalancerStructs.Input public input;

    // Third party contracts
    address public booster;
    address public rewardPool;
    uint256 public pid;
    bool public composable;

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    BeefyBalancerStructs.BatchSwapStruct[] public nativeToLp0Route;
    BeefyBalancerStructs.BatchSwapStruct[] public lp0ToLp1Route;
    BeefyBalancerStructs.BatchSwapStruct[] public outputToNativeRoute;
    address[] public nativeToLp0Assets;
    address[] public lp0Tolp1Assets;
    address[] public outputToNativeAssets;

    mapping(address => BeefyBalancerStructs.Reward) public rewards;
    address[] public rewardTokens;

    address public uniswapRouter;
    bool public earmark;
    bool public shouldSweep;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public totalLocked;

    event StratHarvest(address indexed harvester, uint256 indexed wantHarvested, uint256 indexed tvl);
    event Deposit(uint256 indexed tvl);
    event Withdraw(uint256 indexed tvl);
    event ChargedFees(uint256 indexed callFees, uint256 indexed beefyFees, uint256 indexed strategistFees);

    function initialize(
        address _want,
        BeefyBalancerStructs.BatchSwapStruct[] memory _nativeToLp0Route,
        BeefyBalancerStructs.BatchSwapStruct[] memory _lp0ToLp1Route,
        BeefyBalancerStructs.BatchSwapStruct[] memory _outputToNativeRoute,
        address _booster,
        uint256 _pid,
        address[] memory _nativeToLp0,
        address[] memory _lp0ToLp1,
        address[] memory _outputToNative,
        CommonAddresses calldata _commonAddresses
    ) public initializer  {
        __StratFeeManager_init(_commonAddresses);

        for (uint i; i < _nativeToLp0Route.length; ++i) {
            nativeToLp0Route.push(_nativeToLp0Route[i]);
        }

        for (uint j; j < _lp0ToLp1Route.length; ++j) {
            lp0ToLp1Route.push(_lp0ToLp1Route[j]);
        }

        for (uint k; k < _outputToNativeRoute.length; ++k) {
            outputToNativeRoute.push(_outputToNativeRoute[k]);
        }

        want = _want;
        booster = _booster;
        pid = _pid;
        outputToNativeAssets = _outputToNative;
        nativeToLp0Assets = _nativeToLp0;
        lp0Tolp1Assets = _lp0ToLp1;
        output = outputToNativeAssets[0];
        native = nativeToLp0Assets[0];
        lp0 = lp0Tolp1Assets[0];
        lp1 = lp0Tolp1Assets[lp0Tolp1Assets.length - 1];
        uniswapRouter = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        shouldSweep = true;

        (,,,rewardPool,,) = IAuraBooster(booster).poolInfo(pid);

        swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        _giveAllowances();
    }

    function deposit() public whenNotPaused {
        if (shouldSweep) {
            _deposit();
        }
    }

    // puts the funds to work
    function _deposit() internal whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IAuraBooster(booster).deposit(pid, wantBal, true);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IAuraRewardPool(rewardPool).withdrawAndUnwrap(_amount - wantBal, false);
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
        if (earmark) IAuraBooster(booster).earmarkRewards(pid);
        IAuraRewardPool(rewardPool).getReward();
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        uint256 before = balanceOfWant();

        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant() - before;
            totalLocked = wantHarvested + lockedProfit();
            _deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function swapRewardsToNative() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(outputToNativeRoute, outputBal);
            BalancerActionsLib.balancerSwap(unirouter, swapKind, _swaps, outputToNativeAssets, funds, int256(outputBal));
        }
        // extras
        for (uint i; i < rewardTokens.length; ++i) {
            uint bal = IERC20(rewardTokens[i]).balanceOf(address(this));
            if (bal >= rewards[rewardTokens[i]].minAmount) {
                if (rewards[rewardTokens[i]].assets[0] != address(0)) {
                    BeefyBalancerStructs.BatchSwapStruct[] memory swapInfo = new BeefyBalancerStructs.BatchSwapStruct[](rewards[rewardTokens[i]].assets.length - 1);
                    for (uint j; j < rewards[rewardTokens[i]].assets.length - 1;) {
                        swapInfo[j] = rewards[rewardTokens[i]].swapInfo[j];
                        unchecked {
                            ++j;
                        }
                    }
                    IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(swapInfo, bal);
                    BalancerActionsLib.balancerSwap(unirouter, swapKind, _swaps, rewards[rewardTokens[i]].assets, funds, int256(bal));
                } else {
                    UniV3Actions.swapV3WithDeadline(uniswapRouter, rewards[rewardTokens[i]].routeToNative, bal);
                }
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
    function addLiquidity() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        bytes32 poolId = IBalancerPool(want).getPoolId();
        (address[] memory lpTokens,,) = IBalancerVault(unirouter).getPoolTokens(poolId);

        if (lpTokens[0] != native) {
            IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(nativeToLp0Route, nativeBal);
            BalancerActionsLib.balancerSwap(unirouter, swapKind, _swaps, nativeToLp0Assets, funds, int256(nativeBal));
        }

        if (nativeBal > 0) {
            uint256 lp0Bal = IERC20(lpTokens[0]).balanceOf(address(this));
            (uint256 lp0Amt, uint256 lp1Amt) =  _calcSwapAmount(lp0Bal);

            IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(lp0ToLp1Route, lp1Amt);
            BalancerActionsLib.balancerSwap(unirouter, swapKind, _swaps, lp0Tolp1Assets, funds, int256(lp1Amt));
            
            BalancerActionsLib.multiJoin(unirouter, want, poolId, lpTokens[0], lpTokens[1], lp0Amt, IERC20(lpTokens[1]).balanceOf(address(this)));
        }
    }

    function _calcSwapAmount(uint256 _bal) private view returns (uint256 lp0Amt, uint256 lp1Amt) {
            lp0Amt = _bal / 2;
            lp1Amt = _bal - lp0Amt;

            (uint256 rate0, uint256 rate1) = IBalancerPool(want).getTokenRates();

            (, uint256[] memory balances,) = IBalancerVault(unirouter).getPoolTokens(IBalancerPool(want).getPoolId());
            uint256 supply = IERC20(want).totalSupply();

            uint256 amountA = balances[0] * 1e18 / supply;
            uint256 amountB = balances[1] * 1e18 / supply;
            
            uint256 ratio = rate0 * 1e18 / rate1 * amountB / amountA;
            lp0Amt = _bal * 1e18 / (ratio + 1e18);
            lp1Amt = _bal - lp0Amt;
    }

    function lockedProfit() public view returns (uint256) {
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < DURATION ? DURATION - elapsed : 0;
        return totalLocked * remaining / DURATION;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return IAuraRewardPool(rewardPool).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IAuraRewardPool(rewardPool).earned(address(this));
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0; // multiple swap providers with no easy way to estimate native output.
    }

    function addRewardToken(address _token, BeefyBalancerStructs.BatchSwapStruct[] memory _swapInfo, address[] memory _assets, bytes calldata _routeToNative, uint _minAmount) external onlyOwner {
        require(_token != want, "!want");
        require(_token != native, "!native");
        if (_assets[0] != address(0)) {
            IERC20(_token).safeApprove(unirouter, 0);
            IERC20(_token).safeApprove(unirouter, type(uint).max);
        } else {
            IERC20(_token).safeApprove(uniswapRouter, 0);
            IERC20(_token).safeApprove(uniswapRouter, type(uint).max);
        }

        rewards[_token].assets = _assets;
        rewards[_token].routeToNative = _routeToNative;
        rewards[_token].minAmount = _minAmount;

        for (uint i; i < _swapInfo.length; ++i) {
            rewards[_token].swapInfo[i].poolId = _swapInfo[i].poolId;
            rewards[_token].swapInfo[i].assetInIndex = _swapInfo[i].assetInIndex;
            rewards[_token].swapInfo[i].assetOutIndex = _swapInfo[i].assetOutIndex;
        }
        rewardTokens.push(_token);
    }

    function resetRewardTokens() external onlyManager {
        for (uint i; i < rewardTokens.length; ++i) {
            delete rewards[rewardTokens[i]];
        }
        delete rewardTokens;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    function setEarmark(bool _earmark) external onlyManager {
        earmark = _earmark;
    }

    function setShouldSweep(bool _shouldSweep) external onlyManager {
        shouldSweep = _shouldSweep;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IAuraRewardPool(rewardPool).withdrawAndUnwrap(balanceOfPool(), false);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IAuraRewardPool(rewardPool).withdrawAndUnwrap(balanceOfPool(), false);
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
        IERC20(want).safeApprove(booster, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
        IERC20(native).safeApprove(unirouter, type(uint).max);

        IERC20(lp0).safeApprove(unirouter, 0);
        IERC20(lp0).safeApprove(unirouter, type(uint).max);

        IERC20(lp1).safeApprove(unirouter, 0);
        IERC20(lp1).safeApprove(unirouter, type(uint).max);

        if (rewardTokens.length != 0) {
            for (uint i; i < rewardTokens.length; ++i) {
                if (rewards[rewardTokens[i]].assets[0] != address(0)) {
                    IERC20(rewardTokens[i]).safeApprove(unirouter, 0);
                    IERC20(rewardTokens[i]).safeApprove(unirouter, type(uint).max);
                } else {
                    IERC20(rewardTokens[i]).safeApprove(uniswapRouter, 0);
                    IERC20(rewardTokens[i]).safeApprove(uniswapRouter, type(uint).max);
                }
            }
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(booster, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
        IERC20(lp0).safeApprove(unirouter, 0);
        IERC20(lp1).safeApprove(unirouter, 0);
        if (rewardTokens.length != 0) {
            for (uint i; i < rewardTokens.length; ++i) {
                if (rewards[rewardTokens[i]].assets[0] != address(0)) {
                    IERC20(rewardTokens[i]).safeApprove(unirouter, 0);
                } else {
                    IERC20(rewardTokens[i]).safeApprove(uniswapRouter, 0);
                }
            }
        }
    }
}