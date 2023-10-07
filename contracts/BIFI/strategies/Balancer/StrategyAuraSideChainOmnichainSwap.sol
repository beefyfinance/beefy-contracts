// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";
import "../../interfaces/aura/IAuraRewardPool.sol";
import "../../interfaces/curve/IStreamer.sol";
import "../../interfaces/aura/IAuraBooster.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "./BalancerActionsLib.sol";
import "./BeefyBalancerStructs.sol";
import "../../utils/UniV3Actions.sol";

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
}

interface ISwapper { 
    function swapAura(uint256 _amount) external payable;
    function estimate(uint256 _amount) external view returns (uint256 gasNeeded);
}

contract StrategyAuraSideChainOmnichainSwap is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public output;
    address public aura;
    address public native;

    // Third party contracts
    address public booster;
    address public rewardPool;
    address public uniswapRouter;
    address public swapper;
    uint256 public pid;

    // Balancer Router set up
    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    // Swap details
    BeefyBalancerStructs.Input public input;
    BeefyBalancerStructs.BatchSwapStruct[] public nativeToInputRoute;
    BeefyBalancerStructs.BatchSwapStruct[] public outputToNativeRoute;
    address[] public nativeToInputAssets;
    address[] public outputToNativeAssets;

    // Our needed reward token information
    mapping(address => BeefyBalancerStructs.Reward) public rewards;
    address[] public rewardTokens;

  
    // Some needed state variables
    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public minSwap; 
    uint256 public constant DURATION = 1 days;

    event StratHarvest(address indexed harvester, uint256 indexed wantHarvested, uint256 indexed tvl);
    event Deposit(uint256 indexed tvl);
    event Withdraw(uint256 indexed tvl);
    event ChargedFees(uint256 indexed callFees, uint256 indexed beefyFees, uint256 indexed strategistFees);

    function initialize(
        address _want,
        address _aura,
        bool _inputIsComposable,
        BeefyBalancerStructs.BatchSwapStruct[] memory _nativeToInputRoute,
        BeefyBalancerStructs.BatchSwapStruct[] memory _outputToNativeRoute,
        address _booster,
        address _swapper,
        uint256 _pid,
        address[] memory _nativeToInput,
        address[] memory _outputToNative,
        CommonAddresses calldata _commonAddresses
    ) public initializer  {
        __StratFeeManager_init(_commonAddresses);

        for (uint i; i < _nativeToInputRoute.length; ++i) {
            nativeToInputRoute.push(_nativeToInputRoute[i]);
        }

        for (uint j; j < _outputToNativeRoute.length; ++j) {
            outputToNativeRoute.push(_outputToNativeRoute[j]);
        }

        want = _want;
        aura = _aura;
        booster = _booster;
        pid = _pid;
        outputToNativeAssets = _outputToNative;
        nativeToInputAssets = _nativeToInput;
        output = outputToNativeAssets[0];
        native = nativeToInputAssets[0];
        input.input = nativeToInputAssets[nativeToInputAssets.length - 1];
        input.isComposable = _inputIsComposable;
        uniswapRouter = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        swapper = _swapper;

        (,,,rewardPool,,) = IAuraBooster(booster).poolInfo(pid);

        minSwap = 10 ether;

        swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
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

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256 before = balanceOfWant();
        IAuraRewardPool(rewardPool).getReward();
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant() - before;
            totalLocked = wantHarvested + lockedProfit();
            deposit();

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
                    for (uint j; j < rewards[rewardTokens[i]].assets.length - 1; ++j) {
                        swapInfo[j] = rewards[rewardTokens[i]].swapInfo[j];
                    }
                    IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(swapInfo, bal);
                    BalancerActionsLib.balancerSwap(unirouter, swapKind, _swaps, rewards[rewardTokens[i]].assets, funds, int256(bal));
                } else {
                    UniV3Actions.swapV3(uniswapRouter, rewards[rewardTokens[i]].routeToNative, bal);
                }
            }
        }

        uint256 auraBal = IERC20(aura).balanceOf(address(this));
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        uint256 balanceThis = address(this).balance;
        uint256 gasNeeded = ISwapper(swapper).estimate(auraBal);

        if ((nativeBal + balanceThis) >= gasNeeded) {
            uint256 nativeToWithdraw = gasNeeded <= balanceThis ? 0 : gasNeeded - balanceThis;
            if (auraBal > minSwap) {
                IWrappedNative(native).withdraw(nativeToWithdraw);
                ISwapper(swapper).swapAura{value: gasNeeded}(auraBal);
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
        if (native != input.input) {
            IBalancerVault.BatchSwapStep[] memory _swaps = BalancerActionsLib.buildSwapStructArray(nativeToInputRoute, nativeBal);
            BalancerActionsLib.balancerSwap(unirouter, swapKind, _swaps, nativeToInputAssets, funds, int256(nativeBal));
        }

        if (input.input != want) {
            uint256 inputBal = IERC20(input.input).balanceOf(address(this));
            BalancerActionsLib.balancerJoin(unirouter, IBalancerPool(want).getPoolId(), input.input, inputBal);
        }
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

    function setMinSwap(uint256 _min) external onlyManager {
        minSwap = _min;
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
        IERC20(aura).safeApprove(swapper, type(uint).max);
        if (!input.isComposable) {
            IERC20(input.input).safeApprove(unirouter, 0);
            IERC20(input.input).safeApprove(unirouter, type(uint).max);
        }
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
        IERC20(aura).safeApprove(swapper, 0);
        if (!input.isComposable) {
            IERC20(input.input).safeApprove(unirouter, 0);
        }
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

     // allow this contract to receive ether
    receive() external payable {}
}