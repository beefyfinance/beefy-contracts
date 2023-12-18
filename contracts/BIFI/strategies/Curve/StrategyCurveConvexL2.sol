// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/convex/IConvex.sol";
import "../../interfaces/curve/ICrvMinter.sol";
import "../../interfaces/curve/ICurveRouterV1.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/UniV3Actions.sol";
import "../../utils/UniswapV3Utils.sol";

// Curve L2 strategy switchable between Curve and Convex
contract StrategyCurveConvexL2 is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // this `pid` means we using Curve gauge and not Convex rewardPool
    uint constant public NO_PID = 42069;

    // Tokens used
    address public native;
    address public curveRouter;
    IConvexBoosterL2 public constant booster = IConvexBoosterL2(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ICrvMinter public constant minter = ICrvMinter(0xabC000d88f23Bb45525E447528DBF656A9D55bf5);

    address public want; // curve lpToken
    address public gauge; // curve gauge
    address public rewardPool; // convex base reward pool
    uint public pid; // convex booster poolId

    CurveRoute[] public curveRewards;

    struct RewardV3 {
        address token;
        bytes toNativePath; // uniswap path
        uint minAmount; // minimum amount to be swapped to native
    }
    RewardV3[] public rewardsV3; // rewards swapped via unirouter

    // uniV3 path swapped via unirouter, or 0 to skip and use native via depositToWant
    bytes public nativeToDepositPath;
    // add liquidity via curveRouter, deposit token should match nativeToDepositPath or be native
    CurveRoute public depositToWant;

    bool public isCrvMintable; // if CRV can be minted via Minter (gauge is added to Controller)
    bool public isCurveRewardsClaimable; // if extra rewards in curve gauge should be claimed
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _native,
        address _curveRouter,
        address _want,
        address _gauge,
        uint _pid,
        bytes calldata _nativeToDepositPath,
        CurveRoute[] calldata _rewardsToNative,
        CurveRoute calldata _depositToWant,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        native = _native;
        curveRouter = _curveRouter;
        want = _want;
        gauge = _gauge;
        pid = _pid;

        if (_pid != NO_PID) {
            (,,rewardPool,,) = booster.poolInfo(_pid);
            _approve(want, address(booster), type(uint).max);
        } else {
            isCrvMintable = true;
        }

        for (uint i; i < _rewardsToNative.length; i++) {
            addReward(_rewardsToNative[i].route, _rewardsToNative[i].swapParams, _rewardsToNative[i].minAmount);
        }
        if (_rewardsToNative.length > 1) {
            isCurveRewardsClaimable = true;
        }
        setNativeToDepositPath(_nativeToDepositPath);
        setDepositToWant(_depositToWant.route, _depositToWant.swapParams, _depositToWant.minAmount);

        withdrawalFee = 0;
        harvestOnDeposit = true;
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            if (rewardPool != address(0)) {
                booster.deposit(pid, wantBal);
            } else {
                IRewardsGauge(gauge).deposit(wantBal);
            }
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            _withdraw(_amount - wantBal);
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

    function _withdraw(uint256 _amount) internal {
        if (_amount > 0) {
            if (rewardPool != address(0)) {
                IConvexRewardPool(rewardPool).withdraw(_amount, false);
            } else {
                IRewardsGauge(gauge).withdraw(_amount);
            }
        }
    }

    function _emergencyWithdraw() internal {
        uint amount = balanceOfPool();
        if (amount > 0) {
            if (rewardPool != address(0)) {
                IConvexRewardPool(rewardPool).emergencyWithdraw(amount);
            } else {
                IRewardsGauge(gauge).withdraw(amount);
            }
        }
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin, false);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient, false);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient, bool onDeposit) internal whenNotPaused {
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            _chargeFees(callFeeRecipient);
            _addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            if (!onDeposit) {
                deposit();
            }
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _claim() internal {
        if (rewardPool != address(0)) {
            IConvexRewardPool(rewardPool).getReward(address(this));
        } else {
            if (isCrvMintable) minter.mint(gauge);
            if (isCurveRewardsClaimable) IRewardsGauge(gauge).claim_rewards(address(this));
        }
    }

    function _swapRewardsToNative() internal {
        for (uint i; i < curveRewards.length; ++i) {
            uint bal = IERC20(curveRewards[i].route[0]).balanceOf(address(this));
            if (bal > curveRewards[i].minAmount) {
                ICurveRouterV1(curveRouter).exchange(curveRewards[i].route, curveRewards[i].swapParams, bal, 0);
            }
        }
        for (uint i; i < rewardsV3.length; ++i) {
            uint bal = IERC20(rewardsV3[i].token).balanceOf(address(this));
            if (bal > rewardsV3[i].minAmount) {
                UniV3Actions.swapV3(unirouter, rewardsV3[i].toNativePath, bal);
            }
        }
    }

    // performance fees
    function _chargeFees(address callFeeRecipient) internal {
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
    function _addLiquidity() internal {
        if (nativeToDepositPath.length > 0) {
            uint nativeBal = IERC20(native).balanceOf(address(this));
            UniV3Actions.swapV3(unirouter, nativeToDepositPath, nativeBal);
        }

        uint bal = IERC20(depositToWant.route[0]).balanceOf(address(this));
        if (bal > depositToWant.minAmount) {
            ICurveRouterV1(curveRouter).exchange(depositToWant.route, depositToWant.swapParams, bal, 0);
        }
    }

    function setConvexPid(uint _pid) external onlyOwner {
        _withdraw(balanceOfPool());
        if (_pid != NO_PID) {
            (,,rewardPool,,) = booster.poolInfo(_pid);
            if (IERC20(want).allowance(address(this), address(booster)) == 0) {
                _approve(want, address(booster), type(uint).max);
            }
        } else {
            rewardPool = address(0);
        }
        pid = _pid;
        deposit();
    }

    function setNativeToDepositPath(bytes calldata _nativeToDepositPath) public onlyManager {
        if (_nativeToDepositPath.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToDepositPath);
            require(route[0] == native, "!native");
        }
        nativeToDepositPath = _nativeToDepositPath;
    }

    function setDepositToWant(address[11] calldata _route, uint[5][5] calldata _swapParams, uint minAmount) public onlyManager {
        address token = _route[0];
        _checkSwapToken(token, true);

        depositToWant = CurveRoute(_route, _swapParams, minAmount);
        _approve(token, curveRouter, 0);
        _approve(token, curveRouter, type(uint).max);
    }

    function addReward(address[11] calldata _rewardToNativeRoute, uint[5][5] calldata _swapParams, uint _minAmount) public onlyManager {
        address token = _rewardToNativeRoute[0];
        _checkSwapToken(token, false);

        curveRewards.push(CurveRoute(_rewardToNativeRoute, _swapParams, _minAmount));
        _approve(token, curveRouter, 0);
        _approve(token, curveRouter, type(uint).max);
    }

    function addRewardV3(bytes calldata _rewardToNativePath, uint _minAmount) public onlyManager {
        address[] memory _rewardToNativeRoute = UniswapV3Utils.pathToRoute(_rewardToNativePath);
        address token = _rewardToNativeRoute[0];
        _checkSwapToken(token, false);

        rewardsV3.push(RewardV3(token, _rewardToNativePath, _minAmount));
        _approve(token, unirouter, 0);
        _approve(token, unirouter, type(uint).max);
    }

    function _checkSwapToken(address _token, bool _allowNative) internal view {
        require(_token != want, "!want");
        require(_allowNative || _token != native, "!native");
        require(_token != gauge, "!gauge");
        require(_token != rewardPool, "!rewardPool");
    }

    function resetCurveRewards() external onlyManager {
        delete curveRewards;
    }

    function resetRewardsV3() external onlyManager {
        delete rewardsV3;
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
        if (rewardPool != address(0)) {
            return IConvexRewardPool(rewardPool).balanceOf(address(this));
        } else {
            return IRewardsGauge(gauge).balanceOf(address(this));
        }
    }

    function depositToWantRoute() external view returns (address[11] memory, uint256[5][5] memory, uint) {
        return (depositToWant.route, depositToWant.swapParams, depositToWant.minAmount);
    }

    function curveReward(uint i) external view returns (address[11] memory, uint256[5][5] memory, uint) {
        return (curveRewards[i].route, curveRewards[i].swapParams, curveRewards[i].minAmount);
    }

    function curveRewardsLength() external view returns (uint) {
        return curveRewards.length;
    }

    function rewardV3Route(uint i) external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(rewardsV3[i].toNativePath);
    }

    function rewardsV3Length() external view returns (uint) {
        return rewardsV3.length;
    }

    function setCrvMintable(bool _isCrvMintable) external onlyManager {
        isCrvMintable = _isCrvMintable;
    }

    function setCurveRewardsClaimable(bool _isCurveRewardsClaimable) external onlyManager {
        isCurveRewardsClaimable = _isCurveRewardsClaimable;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(1);
        }
    }

    function rewardsAvailable() external pure returns (uint) {
        return 0;
    }

    function callReward() external pure returns (uint) {
        return 0;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _withdraw(balanceOfPool());
        IERC20(want).transfer(vault, balanceOfWant());
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        _withdraw(balanceOfPool());
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
        uint amount = type(uint).max;
        _approve(want, address(gauge), amount);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal {
        _approve(want, address(gauge), 0);
        _approve(want, address(booster), 0);
        _approve(native, unirouter, 0);
    }

    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).approve(_spender, amount);
    }

}
